#!/usr/bin/env bash
BINARY="/usr/local/bin/olcrtc"
CONFIG_FILE="${CONFIG_FILE:-/opt/olcrtc/config/olcrtc.yaml}"
LOG_DIR="${LOG_DIR:-/opt/olcrtc/logs}"
LOG_FILE="${LOG_DIR}/olcrtc-$(date '+%Y%m%d-%H%M%S').log"
MODE="${OLCRTC_MODE:-srv}"
SUBSCRIPTION_NAME="${SUBSCRIPTION_NAME:-🏳️ | unknown | unknown}"

[[ ! -x "${BINARY}" ]] && { err "Binary not found"; exit 1; }
[[ ! -f "${CONFIG_FILE}" ]] && { err "Config not found"; exit 1; }

echo ""
echo "╔══════════════════════════════════════════════════════════════════╗"
echo "║                      CONNECTION SUMMARY                         ║"
echo "╠══════════════════════════════════════════════════════════════════╣"
printf "║  Subscription: %-48s ║\n" "${SUBSCRIPTION_NAME}"
printf "║  Mode:         %-48s ║\n" "${MODE}"
printf "║  Provider:     %-48s ║\n" "${SELECTED_PROVIDER}"
printf "║  Transport:    %-48s ║\n" "${SELECTED_TRANSPORT}"
printf "║  Instance:     %-48s ║\n" "${SELECTED_INSTANCE:-N/A}"
printf "║  Room ID:      %-48s ║\n" "${ROOM_ID}"
printf "║  Crypto Key:   %-48s ║\n" "${CRYPTO_KEY:0:16}...${CRYPTO_KEY: -8}"
printf "║  DNS:          %-48s ║\n" "${OLCRTC_DNS:-8.8.8.8:53}"
[[ "${MODE}" == "cnc" ]] && \
printf "║  SOCKS5:       %-48s ║\n" "${OLCRTC_SOCKS_HOST:-0.0.0.0}:${OLCRTC_SOCKS_PORT:-1080}"
echo "╠══════════════════════════════════════════════════════════════════╣"
echo "║  olcrtc:// URI:                                                 ║"
echo "  ${OLCRTC_URI}"
echo "╚══════════════════════════════════════════════════════════════════╝"
echo ""

INFO_FILE="${LOG_DIR}/connection-info.txt"
cat > "${INFO_FILE}" <<EOF
SUBSCRIPTION=${SUBSCRIPTION_NAME}
MODE=${MODE}
PROVIDER=${SELECTED_PROVIDER}
TRANSPORT=${SELECTED_TRANSPORT}
INSTANCE=${SELECTED_INSTANCE:-}
ROOM_ID=${ROOM_ID}
CRYPTO_KEY=${CRYPTO_KEY}
OLCRTC_URI=${OLCRTC_URI}
EOF
log "Info → ${INFO_FILE}"

log "Starting olcrtc (${MODE})..."
exec "${BINARY}" "${CONFIG_FILE}" 2>&1 | tee -a "${LOG_FILE}"
