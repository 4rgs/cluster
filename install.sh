#!/usr/bin/env bash
# cluster install.sh — install cluster-web + clusterctl on a Debian/Ubuntu box.
#
# Configuration via environment variables (all have sensible defaults):
#   INSTALL_DIR     — where to put the web UI (default: /opt/cluster-web)
#   CLUSTER_DIR     — where to put clusterctl + cluster.toml (default: /opt/cluster)
#   SERVICE_USER    — Linux user that runs the systemd service (default: clusteruser)
#   CLUSTER_WEB_PORT — port the web UI binds to (default: 4321)
#   CLUSTER_WEB_REPO — git URL of cluster-web (default: current repo)
#   CLUSTER_REPO    — git URL of cluster (default: current repo)
#   NODE_VERSION    — required Node version (default: 24)
#
# Usage:
#   curl -fsSL https://your.host/install.sh | sudo bash
#   INSTALL_DIR=/srv/cluster-web SERVICE_USER=node ./install.sh
#
set -Eeuo pipefail

# === Defaults (overridable via env) =======================================
INSTALL_DIR="${INSTALL_DIR:-/opt/cluster-web}"
CLUSTER_DIR="${CLUSTER_DIR:-/opt/cluster}"
SERVICE_USER="${SERVICE_USER:-clusteruser}"
CLUSTER_WEB_PORT="${CLUSTER_WEB_PORT:-4321}"
CLUSTER_WEB_REPO="${CLUSTER_WEB_REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null || echo "")}"
CLUSTER_REPO="${CLUSTER_REPO:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" remote get-url origin 2>/dev/null || echo "")}"
NODE_VERSION="${NODE_VERSION:-24}"

LOG_PREFIX="[install]"
log()  { echo "$LOG_PREFIX $*" >&2; }
fail() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

# === Sanity checks =========================================================
[[ $EUID -eq 0 ]] || fail "must run as root (use sudo)"
command -v apt-get >/dev/null  || fail "apt-get required (Debian/Ubuntu)"
command -v curl     >/dev/null || fail "curl required"
command -v git      >/dev/null || fail "git required"

# === Reject obviously wrong / dangerous values =============================
case "$SERVICE_USER" in
  root|admin|daemon|www-data|nobody) fail "refusing to run service as user '$SERVICE_USER'";;
esac
[[ "$INSTALL_DIR"  == *"/"* && "$INSTALL_DIR"  != "/proc"* && "$INSTALL_DIR"  != "/sys"* ]] || fail "INSTALL_DIR unsafe: $INSTALL_DIR"
[[ "$CLUSTER_DIR"  == *"/"* && "$CLUSTER_DIR"  != "/proc"* && "$CLUSTER_DIR"  != "/sys"* ]] || fail "CLUSTER_DIR unsafe: $CLUSTER_DIR"

# === Step 1: packages ======================================================
log "installing OS packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
    ca-certificates curl git build-essential python3.11 python3-tomli sudo gnupg

# === Step 2: Node.js (use NodeSource) =====================================
log "installing Node.js ${NODE_VERSION}"
if ! command -v node >/dev/null 2>&1 || ! node --version | grep -qE "^v${NODE_VERSION}\."; then
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | bash -
  apt-get install -y -qq nodejs
fi
node --version || fail "Node ${NODE_VERSION} not installed"
node -e "if (!parseInt(process.versions.node.split('.')[0]) >= ${NODE_VERSION}) process.exit(1)" \
  || fail "Node ${NODE_VERSION} required, got $(node --version)"

# === Step 3: service user ==================================================
log "creating service user '$SERVICE_USER' (no password, no shell)"
if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$INSTALL_DIR" --no-create-home \
          --shell /usr/sbin/nologin --gid nogroup "$SERVICE_USER" \
          || useradd --system --home-dir "$INSTALL_DIR" --no-create-home \
                     --shell /bin/false --gid nogroup "$SERVICE_USER"
fi
mkdir -p "$INSTALL_DIR" "$CLUSTER_DIR"

# === Step 4: clone repos ===================================================
log "cloning cluster-web → $INSTALL_DIR"
if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "  existing git repo in $INSTALL_DIR — pulling latest"
  (cd "$INSTALL_DIR" && git pull --ff-only)
else
  if [[ -n "$CLUSTER_WEB_REPO" ]]; then
    git clone "$CLUSTER_WEB_REPO" "$INSTALL_DIR"
  else
    fail "no existing $INSTALL_DIR and CLUSTER_WEB_REPO not set — please pass it"
  fi
fi

log "installing cluster → $CLUSTER_DIR"
if [[ -d "$CLUSTER_DIR/bin" ]]; then
  log "  $CLUSTER_DIR/bin exists — assuming fresh from elsewhere, leaving as-is"
else
  if [[ -n "$CLUSTER_REPO" ]]; then
    git clone "$CLUSTER_REPO" "$CLUSTER_DIR"
  else
    fail "no existing $CLUSTER_DIR and CLUSTER_REPO not set — please pass it"
  fi
fi
chmod +x "$CLUSTER_DIR/bin/"*

# === Step 5: render systemd service from template =========================
log "rendering systemd service from template"
TEMPLATE="$INSTALL_DIR/cluster-web.service.template"
RENDERED="/etc/systemd/system/cluster-web.service"
[[ -f "$TEMPLATE" ]] || fail "template not found: $TEMPLATE"

sed -e "s|\${SERVICE_USER}|$SERVICE_USER|g" \
    -e "s|\${INSTALL_DIR}|$INSTALL_DIR|g" \
    -e "s|\${CLUSTER_DIR}|$CLUSTER_DIR|g" \
    -e "s|\${CLUSTER_WEB_PORT}|$CLUSTER_WEB_PORT|g" \
    "$TEMPLATE" > "$RENDERED"
chmod 644 "$RENDERED"

# === Step 6: dependencies + build ==========================================
log "installing npm dependencies + building"
(cd "$INSTALL_DIR" && npm ci && npm run build)

# === Step 7: data dir + permissions =======================================
log "preparing data directory"
mkdir -p "$INSTALL_DIR/data/sessions" "$CLUSTER_DIR/logs"
# Clusterctl log file needs to be writable by service user
touch "$CLUSTER_DIR/logs/ask.log"
chown -R "$SERVICE_USER:nogroup" "$INSTALL_DIR" "$CLUSTER_DIR" 2>/dev/null \
  || chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR" "$CLUSTER_DIR"

# === Step 8: enable + start ===============================================
log "enabling and starting service"
systemctl daemon-reload
systemctl enable cluster-web.service
systemctl restart cluster-web.service

# === Step 9: health check ==================================================
log "waiting for service to be healthy"
for i in {1..15}; do
  if curl -sf --max-time 3 "http://127.0.0.1:${CLUSTER_WEB_PORT}/api/health" >/dev/null 2>&1; then
    log "✓ cluster-web is alive on http://127.0.0.1:${CLUSTER_WEB_PORT}"
    break
  fi
  sleep 1
done

if ! curl -sf --max-time 3 "http://127.0.0.1:${CLUSTER_WEB_PORT}/api/health" >/dev/null 2>&1; then
  log "✗ health check failed — last 30 lines of journal:"
  journalctl -u cluster-web -n 30 --no-pager >&2 || true
  fail "service did not become healthy"
fi

cat <<EOF

================================================================
 ✓ Cluster install complete
================================================================

Service:        systemctl status cluster-web
Health:         curl http://127.0.0.1:${CLUSTER_WEB_PORT}/api/health
Web UI:         http://127.0.0.1:${CLUSTER_WEB_PORT}/
Clusterctl:     ${CLUSTER_DIR}/bin/clusterctl health
Config file:    ${CLUSTER_DIR}/cluster.toml
Logs (systemd): journalctl -u cluster-web -f

Next step: configure your nodes
  sudo CLUSTER_DIR=$CLUSTER_DIR $CLUSTER_DIR/scripts/configure.sh
================================================================
EOF
