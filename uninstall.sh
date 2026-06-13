#!/usr/bin/env bash
# cluster uninstall.sh — remove cluster-web from a Debian/Ubuntu box.
#
# Configuration via environment variables:
#   INSTALL_DIR   — where cluster-web was installed (default: /opt/cluster-web)
#   CLUSTER_DIR   — where clusterctl + cluster.toml live (default: /opt/cluster)
#   SERVICE_USER  — the user the service runs as (default: clusteruser)
#   PURGE_DATA    — set to 1 to also delete the SQLite DB and the cluster.toml
#                   (default: 0 — keeps the data so you can reinstall later)
#
# Usage:
#   sudo ./uninstall.sh
#   PURGE_DATA=1 sudo ./uninstall.sh
#
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/cluster-web}"
CLUSTER_DIR="${CLUSTER_DIR:-/opt/cluster}"
SERVICE_USER="${SERVICE_USER:-clusteruser}"
PURGE_DATA="${PURGE_DATA:-0}"

LOG_PREFIX="[uninstall]"
log()  { echo "$LOG_PREFIX $*" >&2; }
fail() { echo "$LOG_PREFIX ERROR: $*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || fail "must run as root (use sudo)"

# === Stop + disable service ===============================================
if systemctl list-unit-files cluster-web.service 2>/dev/null | grep -q cluster-web; then
  log "stopping cluster-web.service"
  systemctl stop cluster-web.service || true
  systemctl disable cluster-web.service || true
  log "removing /etc/systemd/system/cluster-web.service"
  rm -f /etc/systemd/system/cluster-web.service
  systemctl daemon-reload
else
  log "cluster-web.service not installed (skipping)"
fi

# === Remove install dir ====================================================
if [[ -d "$INSTALL_DIR" ]]; then
  if [[ "$PURGE_DATA" == "1" ]]; then
    log "removing $INSTALL_DIR (including data)"
    rm -rf "$INSTALL_DIR"
  else
    log "preserving $INSTALL_DIR (data kept — set PURGE_DATA=1 to remove)"
  fi
fi

# === Remove cluster dir ====================================================
if [[ -d "$CLUSTER_DIR" ]]; then
  if [[ "$PURGE_DATA" == "1" ]]; then
    log "removing $CLUSTER_DIR (including cluster.toml)"
    rm -rf "$CLUSTER_DIR"
  else
    log "preserving $CLUSTER_DIR (config kept — set PURGE_DATA=1 to remove)"
  fi
fi

# === Remove service user ===================================================
if id -u "$SERVICE_USER" >/dev/null 2>&1; then
  if [[ "$PURGE_DATA" == "1" ]]; then
    log "removing service user '$SERVICE_USER'"
    userdel "$SERVICE_USER" 2>/dev/null || true
  fi
fi

cat <<EOF

================================================================
 ✓ Cluster uninstall complete
================================================================
EOF
