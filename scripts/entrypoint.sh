#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="/opt/olcrtc/scripts"
CONFIG_DIR="/opt/olcrtc/config"
LOG_DIR="/opt/olcrtc/logs"
CONFIG_FILE="${CONFIG_DIR}/olcrtc.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARN:${NC} $*"; }
err()  { echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $*" >&2; }

mkdir -p "${CONFIG_DIR}" "${LOG_DIR}"

echo ""
echo "============================================================"
echo "  olcrtc — Automated WebRTC Tunnel Server"
echo "  $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "============================================================"
echo ""

# ── PHASE 2 — Validate providers ──
log "═══ PHASE 2: Validating providers ═══"

SKIP_CHECK=false
if [[ -n "${OLCRTC_PROVIDER}" && -n "${OLCRTC_ROOM_ID}" && -n "${OLCRTC_CRYPTO_KEY}" ]]; then
    warn "Full ENV connection data → skipping auto-detection"
    SKIP_CHECK=true
    SELECTED_PROVIDER="${OLCRTC_PROVIDER}"
    SELECTED_TRANSPORT="${OLCRTC_TRANSPORT:-datachannel}"
    SELECTED_INSTANCE="${OLCRTC_JITSI_INSTANCE:-}"
    SELECTED_ROOM_ID="${OLCRTC_ROOM_ID}"
    SELECTED_FLAG="🏳️"
    HOST_LABEL=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "olcrtc-node")
    SUBSCRIPTION_NAME="${SELECTED_FLAG} | ${SELECTED_PROVIDER} | ${SELECTED_TRANSPORT} / ${HOST_LABEL}"
fi

if [[ "${SKIP_CHECK}" == "false" ]]; then
    source "${SCRIPTS_DIR}/check-providers.sh"
fi

# ENV overrides (only non-empty)
[[ -n "${OLCRTC_PROVIDER}" ]]       && SELECTED_PROVIDER="${OLCRTC_PROVIDER}"
[[ -n "${OLCRTC_TRANSPORT}" ]]      && SELECTED_TRANSPORT="${OLCRTC_TRANSPORT}"
[[ -n "${OLCRTC_JITSI_INSTANCE}" ]] && SELECTED_INSTANCE="${OLCRTC_JITSI_INSTANCE}"
[[ -n "${OLCRTC_ROOM_ID}" ]]        && SELECTED_ROOM_ID="${OLCRTC_ROOM_ID}"

# Rebuild subscription after overrides
HOST_LABEL="${HOST_LABEL:-$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "olcrtc-node")}"
SELECTED_FLAG="${SELECTED_FLAG:-🏳️}"
SUBSCRIPTION_NAME="${SELECTED_FLAG} | ${SELECTED_PROVIDER} | ${SELECTED_TRANSPORT} / ${HOST_LABEL}"

log "Provider:     ${SELECTED_PROVIDER}"
log "Transport:    ${SELECTED_TRANSPORT}"
log "Instance:     ${SELECTED_INSTANCE:-N/A}"
log "Room ID:      ${SELECTED_ROOM_ID:-will be generated}"
log "Subscription: ${SUBSCRIPTION_NAME}"
echo ""

# ── PHASE 3 — Generate configuration ──
log "═══ PHASE 3: Generating configuration ═══"
source "${SCRIPTS_DIR}/generate-config.sh"

log "Config:    ${CONFIG_FILE}"
log "Crypto:    ${CRYPTO_KEY:0:8}...${CRYPTO_KEY: -8}"
log "Room ID:   ${ROOM_ID}"
echo ""

# ── PHASE 4 — Launch server ──
log "═══ PHASE 4: Launching olcrtc server ═══"
source "${SCRIPTS_DIR}/run-server.sh"
