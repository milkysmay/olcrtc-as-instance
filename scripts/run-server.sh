#!/usr/bin/env bash
# Phase 4: Launch olcrtc + log connection info + olcrtc:// URI

BINARY="/usr/local/bin/olcrtc"
CONFIG_FILE="${CONFIG_FILE:-/opt/olcrtc/config/olcrtc.yaml}"
LOG_DIR="${LOG_DIR:-/opt/olcrtc/logs}"
LOG_FILE="${LOG_DIR}/olcrtc-$(date '+%Y%m%d-%H%M%S').log"
MODE="${OLCRTC_MODE:-srv}"

[[ ! -x "${BINARY}" ]] && { err "Binary not found at ${BINARY}"; exit 1; }
[[ ! -f "${CONFIG_FILE}" ]] && { err "Config not found"; exit 1; }

# Connection summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    CONNECTION SUMMARY                       ║"
echo "╠══════════════════════════════════════════════════════════════╣"
printf "║  Mode:       %-44s ║\n" "${MODE}"
printf "║  Provider:   %-44s ║\n" "${SELECTED_PROVIDER}"
printf "║  Transport:  %-44s ║\n" "${SELECTED_TRANSPORT}"
printf "║  Room ID:    %-44s ║\n" "${ROOM_ID}"
printf "║  Crypto Key: %-44s ║\n" "${CRYPTO_KEY:0:16}...${CRYPTO_KEY: -8}"
printf "║  DNS:        %-44s ║\n" "${OLCRTC_DNS:-8.8.8.8:53}"
[[ "${MODE}" == "cnc" ]] && printf "║  SOCKS5:     %-44s ║\n" "${OLCRTC_SOCKS_HOST:-0.0.0.0}:${OLCRTC_SOCKS_PORT:-1080}"
echo "╠══════════════════════════════════════════════════════════════╣"
echo "║  olcrtc:// URI (share with client):                         ║"
echo "  ${OLCRTC_URI}"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Save to file
INFO_FILE="${LOG_DIR}/connection-info.txt"
cat > "${INFO_FILE}" <<EOF
MODE=${MODE}
PROVIDER=${SELECTED_PROVIDER}
TRANSPORT=${SELECTED_TRANSPORT}
ROOM_ID=${ROOM_ID}
CRYPTO_KEY=${CRYPTO_KEY}
OLCRTC_URI=${OLCRTC_URI}
EOF
log "Connection info saved to: ${INFO_FILE}"

# Launch
log "Starting olcrtc (${MODE})..."
exec "${BINARY}" "${CONFIG_FILE}" 2>&1 | tee -a "${LOG_FILE}"
