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

# ── Subscription ──
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

# ── Transport options (all overridable via ENV) ──
case "${SELECTED_TRANSPORT}" in
    vp8channel)
        printf '\nvp8:\n  fps: %s\n  batch_size: %s\n' \
            "${OLCRTC_VP8_FPS:-30}" "${OLCRTC_VP8_BATCH_SIZE:-64}" >> "${CONFIG_FILE}"
        ;;
    seichannel)
        printf '\nsei:\n  fps: %s\n  batch_size: %s\n  fragment_size: %s\n  ack_timeout_ms: %s\n' \
            "${OLCRTC_SEI_FPS:-30}" "${OLCRTC_SEI_BATCH_SIZE:-64}" \
            "${OLCRTC_SEI_FRAGMENT_SIZE:-900}" "${OLCRTC_SEI_ACK_TIMEOUT_MS:-2000}" >> "${CONFIG_FILE}"
        ;;
    videochannel)
        printf '\nvideo:\n  codec: %s\n  width: %s\n  height: %s\n  fps: %s\n  bitrate: "%s"\n  hw: %s\n' \
            "${OLCRTC_VIDEO_CODEC:-qrcode}" "${OLCRTC_VIDEO_WIDTH:-1080}" \
            "${OLCRTC_VIDEO_HEIGHT:-1080}" "${OLCRTC_VIDEO_FPS:-30}" \
            "${OLCRTC_VIDEO_BITRATE:-5000k}" "${OLCRTC_VIDEO_HW:-none}" >> "${CONFIG_FILE}"
        ;;
esac

# ── SOCKS5 (client mode) ──
if [[ "${MODE}" == "cnc" ]]; then
    printf '\nsocks:\n  host: "%s"\n  port: %s\n' \
        "${OLCRTC_SOCKS_HOST:-0.0.0.0}" "${OLCRTC_SOCKS_PORT:-1080}" >> "${CONFIG_FILE}"
    [[ -n "${OLCRTC_SOCKS_USER:-}" ]] && printf '  user: %s\n  pass: %s\n' \
        "${OLCRTC_SOCKS_USER}" "${OLCRTC_SOCKS_PASS:-}" >> "${CONFIG_FILE}"
fi

# ── Upstream proxy (server mode) ──
if [[ "${MODE}" == "srv" && -n "${OLCRTC_UPSTREAM_PROXY_ADDR:-}" ]]; then
    printf '\nsocks:\n  proxy_addr: "%s"\n  proxy_port: %s\n' \
        "${OLCRTC_UPSTREAM_PROXY_ADDR}" "${OLCRTC_UPSTREAM_PROXY_PORT:-1080}" >> "${CONFIG_FILE}"
fi

# ── olcrtc:// URI (no $auto) ──
PAYLOAD=""
case "${SELECTED_TRANSPORT}" in
    vp8channel)   PAYLOAD="<vp8-fps=${OLCRTC_VP8_FPS:-30}&vp8-batch=${OLCRTC_VP8_BATCH_SIZE:-64}>" ;;
    seichannel)   PAYLOAD="<fps=${OLCRTC_SEI_FPS:-30}&batch=${OLCRTC_SEI_BATCH_SIZE:-64}&frag=${OLCRTC_SEI_FRAGMENT_SIZE:-900}&ack-ms=${OLCRTC_SEI_ACK_TIMEOUT_MS:-2000}>" ;;
    videochannel) PAYLOAD="<video-w=${OLCRTC_VIDEO_WIDTH:-1080}&video-h=${OLCRTC_VIDEO_HEIGHT:-1080}&video-fps=${OLCRTC_VIDEO_FPS:-30}&video-bitrate=${OLCRTC_VIDEO_BITRATE:-5000k}&video-hw=${OLCRTC_VIDEO_HW:-none}&video-codec=${OLCRTC_VIDEO_CODEC:-qrcode}>" ;;
esac

OLCRTC_URI="olcrtc://${SELECTED_PROVIDER}?${SELECTED_TRANSPORT}${PAYLOAD}@${ROOM_ID}#${CRYPTO_KEY} / ${SUBSCRIPTION_NAME}"

export CRYPTO_KEY ROOM_ID OLCRTC_URI CONFIG_FILE SUBSCRIPTION_NAME SELECTED_FLAG HOST_LABEL

log "Config:"
cat "${CONFIG_FILE}"
