#!/usr/bin/env bash
# cluster check.sh — diagnose the cluster-web install.
#
# Verifies: systemd unit, port, health endpoint, DB integrity, and node reachability.
# Returns 0 if everything is healthy, non-zero otherwise.
#
# Configuration via env:
#   INSTALL_DIR  — where cluster-web is installed (default: /opt/cluster-web)
#   CLUSTER_DIR  — where clusterctl lives (default: /opt/cluster)
#   CLUSTER_WEB_PORT — port (default: 4321)
#
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/cluster-web}"
CLUSTER_DIR="${CLUSTER_DIR:-/opt/cluster}"
CLUSTER_WEB_PORT="${CLUSTER_WEB_PORT:-4321}"

LOG_PREFIX="[check]"
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
RESET='\033[0m'

pass=0
fail=0
section() { echo; echo "── $* ──"; }
ok()     { echo -e "  ${GREEN}✓${RESET} $*"; pass=$((pass+1)); }
bad()    { echo -e "  ${RED}✗${RESET} $*"; fail=$((fail+1)); }
warn()   { echo -e "  ${YELLOW}!${RESET} $*"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }
node_bin="${INSTALL_DIR}/.local/node-bin/node"

# === Section 1: systemd service ===========================================
section "systemd service"
if have_cmd systemctl; then
  if systemctl list-unit-files cluster-web.service 2>/dev/null | grep -q cluster-web; then
    ok "cluster-web.service unit is installed"
    if systemctl is-active --quiet cluster-web; then
      ok "cluster-web is active"
    else
      bad "cluster-web is NOT active — systemctl status cluster-web"
    fi
  else
    bad "cluster-web.service not found in /etc/systemd/system"
  fi
else
  warn "systemctl not available (not on systemd?)"
fi

# === Section 2: listening port =============================================
section "listening port ${CLUSTER_WEB_PORT}"
if have_cmd ss && ss -tln "sport = :${CLUSTER_WEB_PORT}" 2>/dev/null | grep -q LISTEN; then
  ok "port ${CLUSTER_WEB_PORT} is listening"
elif have_cmd netstat && netstat -tln 2>/dev/null | grep -q ":${CLUSTER_WEB_PORT} "; then
  ok "port ${CLUSTER_WEB_PORT} is listening"
else
  bad "port ${CLUSTER_WEB_PORT} is NOT listening"
fi

# === Section 3: health endpoint ============================================
section "health endpoint"
if health=$(curl -sf --max-time 5 "http://127.0.0.1:${CLUSTER_WEB_PORT}/api/health" 2>/dev/null); then
  ok "GET /api/health returned 200"
  cluster=$(echo "$health" | grep -oE '"cluster":"[^"]+"' | head -1 | cut -d'"' -f4)
  [[ -n "$cluster" ]] && ok "cluster name: $cluster" || warn "no cluster name in response"
  slaves=$(echo "$health" | grep -oE '"name":"[^"]+"' | wc -l)
  ok "$slaves slave(s) reported in health"
else
  bad "GET /api/health failed (curl exit non-zero)"
fi

# === Section 4: clusterctl binary =========================================
section "clusterctl"
if [[ -x "$CLUSTER_DIR/bin/clusterctl" ]]; then
  ok "clusterctl exists and is executable at $CLUSTER_DIR/bin/clusterctl"
  if have_cmd python3; then
    if "$CLUSTER_DIR/bin/clusterctl" health >/dev/null 2>&1; then
      ok "clusterctl health ran cleanly"
    else
      warn "clusterctl health exited non-zero (some nodes may be down — see /api/health)"
    fi
  else
    warn "python3 not found — skipping clusterctl runtime test"
  fi
else
  bad "clusterctl not found at $CLUSTER_DIR/bin/clusterctl"
fi

# === Section 5: SQLite database ============================================
section "SQLite database"
db="${INSTALL_DIR}/data/cluster.db"
if [[ -f "$db" ]]; then
  ok "cluster.db exists ($db)"
  if [[ -x "$node_bin" ]]; then
    n_sessions=$("$node_bin" --experimental-sqlite --no-warnings -e "
      const {DatabaseSync}=require('node:sqlite');
      const db=new DatabaseSync('$db');
      console.log(db.prepare('SELECT COUNT(*) as n FROM sessions').get().n);
    " 2>/dev/null || echo "?")
    if [[ "$n_sessions" =~ ^[0-9]+$ ]]; then
      ok "DB readable: $n_sessions session(s)"
    else
      warn "DB exists but node:sqlite query failed (Node 22+ required)"
    fi
  else
    warn "Node 22+ not found at $node_bin — skipping DB query"
  fi
else
  warn "cluster.db does not exist yet (will be created on first ask)"
fi

# === Section 6: config file ===============================================
section "config file"
toml="${CLUSTER_DIR}/cluster.toml"
if [[ -f "$toml" ]]; then
  ok "cluster.toml exists at $toml"
  n_nodes=$(grep -c "^\[\[node\]\]" "$toml" 2>/dev/null || echo 0)
  ok "$n_nodes node(s) configured"
else
  warn "cluster.toml does not exist — run $CLUSTER_DIR/scripts/configure.sh"
fi

# === Summary ==============================================================
echo
echo "════════════════════════════════════════════════════════════════"
if [[ $fail -eq 0 ]]; then
  echo -e "${GREEN}✓ all checks passed${RESET} ($pass ok)"
  exit 0
else
  echo -e "${RED}✗ $fail check(s) failed${RESET} ($pass ok)"
  echo
  echo "  Tips:"
  echo "  - systemctl status cluster-web"
  echo "  - journalctl -u cluster-web -n 50 --no-pager"
  exit 1
fi
