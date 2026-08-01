#!/usr/bin/env bash
SCRIPTS_DIR="${SCRIPTS_DIR:-/opt/olcrtc/scripts}"
CONFIG_DIR="${CONFIG_DIR:-/opt/olcrtc/config}"
CONFIG_FILE="${CONFIG_FILE:-${CONFIG_DIR}/olcrtc.yaml}"

# ── Crypto key ──
if [[ -n "${OLCRTC_CRYPTO_KEY:-}" ]]; then
    CRYPTO_KEY="${OLCRTC_CRYPTO_KEY}"
    log "Crypto key: from ENV"
else
    CRYPTO_KEY=$(openssl rand -hex 32)
    log "Crypto key: generated"
fi
[[ ${#CRYPTO_KEY} -ne 64 ]] && { err "Key must be 64 hex chars"; exit 1; }

# ── Room ID ──
if [[ -n "${OLCRTC_ROOM_ID:-}" ]]; then
    ROOM_ID="${OLCRTC_ROOM_ID}"
else
    ROOM_NAME=$(bash "${SCRIPTS_DIR}/generate-room-name.sh")
    case "${SELECTED_PROVIDER}" in
        jitsi) ROOM_ID="https://${SELECTED_INSTANCE:-meet.egovm.ru}/${ROOM_NAME}" ;;
        *)     ROOM_ID="${ROOM_NAME}" ;;
    esac
    log "Room ID: ${ROOM_ID}"
fi

# ── Subscription name ──
HOST_LABEL="${HOST_LABEL:-$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "olcrtc-node")}"
SELECTED_FLAG="${SELECTED_FLAG:-🏳️}"
SUBSCRIPTION_NAME="${SELECTED_FLAG} | ${SELECTED_PROVIDER} | ${SELECTED_TRANSPORT} / ${HOST_LABEL}"
log "Subscription: ${SUBSCRIPTION_NAME}"

DNS="${OLCRTC_DNS:-8.8.8.8:53}"
MODE="${OLCRTC_MODE:-srv}"

# ── YAML ──
cat > "${CONFIG_FILE}" <<EOF
# ${SUBSCRIPTION_NAME}
mode: ${MODE}
auth:
  provider: ${SELECTED_PROVIDER}
room:
  id: "${ROOM_ID}"
crypto:
  key: "${CRYPTO_KEY}"
net:
  transport: ${SELECTED_TRANSPORT}
  dns: "${DNS}"
data: data
EOF

[[ "${OLCRTC_DEBUG:-true}" == "true" ]] && echo -e "\ndebug: true" >> "${CONFIG_FILE}"

case "${SELECTED_TRANSPORT}" in
    vp8channel)   printf '\nvp8:\n  fps: 30\n  batch_size: 64\n' >> "${CONFIG_FILE}" ;;
    seichannel)   printf '\nsei:\n  fps: 30\n  batch_size: 64\n  fragment_size: 900\n  ack_timeout_ms: 2000\n' >> "${CONFIG_FILE}" ;;
    videochannel) printf '\nvideo:\n  codec: qrcode\n  width: 1080\n  height: 1080\n  fps: 30\n  bitrate: "5000k"\n  hw: none\n' >> "${CONFIG_FILE}" ;;
esac

if [[ "${MODE}" == "cnc" ]]; then
    printf '\nsocks:\n  host: "%s"\n  port: %s\n' \
        "${OLCRTC_SOCKS_HOST:-0.0.0.0}" "${OLCRTC_SOCKS_PORT:-1080}" >> "${CONFIG_FILE}"
    [[ -n "${OLCRTC_SOCKS_USER:-}" ]] && printf '  user: %s\n  pass: %s\n' \
        "${OLCRTC_SOCKS_USER}" "${OLCRTC_SOCKS_PASS:-}" >> "${CONFIG_FILE}"
fi

if [[ "${MODE}" == "srv" && -n "${OLCRTC_UPSTREAM_PROXY_ADDR:-}" ]]; then
    printf '\nsocks:\n  proxy_addr: "%s"\n  proxy_port: %s\n' \
        "${OLCRTC_UPSTREAM_PROXY_ADDR}" "${OLCRTC_UPSTREAM_PROXY_PORT:-1080}" >> "${CONFIG_FILE}"
fi

# ── olcrtc:// URI (no $auto) ──
PAYLOAD=""
case "${SELECTED_TRANSPORT}" in
    vp8channel)   PAYLOAD="<vp8-fps=30&vp8-batch=64>" ;;
    seichannel)   PAYLOAD="<fps=30&batch=64&frag=900&ack-ms=2000>" ;;
    videochannel) PAYLOAD="<video-w=1080&video-h=1080&video-fps=30&video-bitrate=5000k&video-hw=none&video-codec=qrcode>" ;;
esac

OLCRTC_URI="olcrtc://${SELECTED_PROVIDER}?${SELECTED_TRANSPORT}${PAYLOAD}@${ROOM_ID}#${CRYPTO_KEY} / ${SUBSCRIPTION_NAME}"

export CRYPTO_KEY ROOM_ID OLCRTC_URI CONFIG_FILE SUBSCRIPTION_NAME SELECTED_FLAG HOST_LABEL

log "Config:"
cat "${CONFIG_FILE}"
