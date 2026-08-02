#!/usr/bin/env bash
# Phase 2: Validate providers by ACTUALLY launching olcrtc.
#   Step 1 — ping pre-filter
#   Step 2 — real validation via olcrtc (detailed logging)
#   Step 3 — country flag + subscription name
#
# OLCRTC_TEST_ALL_PROVIDERS=true → also validate telemost/wbstream
#   even when jitsi already passed (diagnostics only).

OLCRTC_BIN="/usr/local/bin/olcrtc"
VALIDATE_WAIT=12          # seconds (was 6 — too short for WebRTC ICE)
MAX_VALIDATE_CANDIDATES=5
PING_TIMEOUT=3; PING_COUNT=2; CURL_TIMEOUT=5

JITSI_INSTANCES=(
    "meet.egovm.ru"
    "conference.ct.placetime.team"
    "jitsy.amateusfox.online"
    "meet.mamba.group"
    "meet.ecopsy.com"
    "meet.mirox.chat"
    "webinar.knomary.dev"
    "meet.playform.ru"
    "webinar.devknomarylms.ru"
    "zgn-y-vc01.zignotch.com"
    "conf.expressmoney.com"
    "m.catonmoon.com"
    "conf.hyperia.space"
    "jitsi.etudevs.ru"
    "meet.riddlerx.org"
)

OTHER_PROVIDERS=(
    "telemost:telemost.yandex.ru:vp8channel"
    "wbstream:stream.wb.ru:datachannel"
)

# ──────────────────────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────────────────────

measure_latency_us() {
    local host="$1" latency_ms=""
    if command -v ping &>/dev/null; then
        latency_ms=$(ping -c "${PING_COUNT}" -W "${PING_TIMEOUT}" "${host}" 2>/dev/null \
            | grep -oP 'time=\K[0-9.]+' | sort -n | head -1)
    fi
    if [[ -z "${latency_ms}" ]]; then
        local s
        s=$(curl -o /dev/null -s -w '%{time_connect}' \
            --connect-timeout "${CURL_TIMEOUT}" "https://${host}/" 2>/dev/null || echo "")
        if [[ -n "${s}" && "${s}" != "0.000000" ]]; then
            latency_ms=$(awk "BEGIN{printf \"%.0f\",${s}*1000}" 2>/dev/null || echo "")
        fi
    fi
    [[ -n "${latency_ms}" ]] && awk "BEGIN{printf \"%.0f\",${latency_ms}*1000}" 2>/dev/null
}

check_http() {
    local code
    code=$(curl -o /dev/null -s -w '%{http_code}' \
        --connect-timeout "${CURL_TIMEOUT}" "https://$1/" 2>/dev/null || echo "000")
    [[ "${code}" != "000" ]]
}

resolve_ip() {
    local host="$1" ip=""
    ip=$(dig +short "${host}" A 2>/dev/null | grep -oP '^\d+\.\d+\.\d+\.\d+$' | head -1)
    [[ -z "${ip}" ]] && ip=$(getent hosts "${host}" 2>/dev/null | awk '{print $1}' | head -1)
    echo "${ip}"
}

country_to_flag() {
    local cc="${1^^}"
    [[ ${#cc} -ne 2 ]] && { echo "🏳️"; return; }
    local flag=""
    flag=$(python3 -c "print(''.join(chr(0x1F1E6+ord(c)-65) for c in '${cc}'))" 2>/dev/null)
    if [[ -z "${flag}" ]]; then
        local i c ascii code hex
        for (( i=0; i<2; i++ )); do
            c="${cc:$i:1}"; ascii=$(printf '%d' "'${c}")
            code=$(( 0x1F1E6 + ascii - 65 )); hex=$(printf '%08x' "${code}")
            flag+="$(printf "\\U${hex}" 2>/dev/null)"
        done
    fi
    [[ -n "${flag}" ]] && echo "${flag}" || echo "🏳️"
}

get_flag_for_host() {
    local host="$1" ip cc=""
    ip=$(resolve_ip "${host}")
    [[ -z "${ip}" ]] && { echo "🏳️"; return; }
    cc=$(curl -s --connect-timeout 3 "http://ip-api.com/json/${ip}?fields=countryCode" 2>/dev/null \
        | grep -oP '"countryCode"\s*:\s*"\K[A-Z]{2}')
    [[ -z "${cc}" ]] && cc=$(curl -s --connect-timeout 3 "https://ipwho.is/${ip}" 2>/dev/null \
        | grep -oP '"country_code"\s*:\s*"\K[A-Z]{2}')
    [[ -n "${cc}" ]] && country_to_flag "${cc}" || echo "🏳️"
}

# ──────────────────────────────────────────────────────────────────────────────
# Write transport-specific config block (uses ENV overrides)
# ──────────────────────────────────────────────────────────────────────────────
write_transport_block() {
    local transport="$1" cfg="$2"
    case "${transport}" in
        vp8channel)
            printf '\nvp8:\n  fps: %s\n  batch_size: %s\n' \
                "${OLCRTC_VP8_FPS:-30}" "${OLCRTC_VP8_BATCH_SIZE:-64}" >> "${cfg}"
            ;;
        seichannel)
            printf '\nsei:\n  fps: %s\n  batch_size: %s\n  fragment_size: %s\n  ack_timeout_ms: %s\n' \
                "${OLCRTC_SEI_FPS:-30}" "${OLCRTC_SEI_BATCH_SIZE:-64}" \
                "${OLCRTC_SEI_FRAGMENT_SIZE:-900}" "${OLCRTC_SEI_ACK_TIMEOUT_MS:-2000}" >> "${cfg}"
            ;;
        videochannel)
            printf '\nvideo:\n  codec: %s\n  width: %s\n  height: %s\n  fps: %s\n  bitrate: "%s"\n  hw: %s\n' \
                "${OLCRTC_VIDEO_CODEC:-qrcode}" "${OLCRTC_VIDEO_WIDTH:-1080}" \
                "${OLCRTC_VIDEO_HEIGHT:-1080}" "${OLCRTC_VIDEO_FPS:-30}" \
                "${OLCRTC_VIDEO_BITRATE:-5000k}" "${OLCRTC_VIDEO_HW:-none}" >> "${cfg}"
            ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────────
# Real validation with DETAILED logging
# ──────────────────────────────────────────────────────────────────────────────
validate_with_olcrtc() {
    local provider="$1" transport="$2" instance="$3"
    local test_key test_room room_id tmp_cfg tmp_log pid
    local elapsed=0 success=false

    test_key=$(openssl rand -hex 32)
    test_room="validate-${RANDOM}-$(date +%s)"

    case "${provider}" in
        jitsi) room_id="https://${instance}/${test_room}" ;;
        *)     room_id="${test_room}" ;;
    esac

    tmp_cfg="/tmp/olcrtc-val-${provider}-${RANDOM}.yaml"
    tmp_log="/tmp/olcrtc-val-${provider}-${RANDOM}.log"

    # ── Write config ──
    cat > "${tmp_cfg}" <<EOF
mode: srv
auth:
  provider: ${provider}
room:
  id: "${room_id}"
crypto:
  key: "${test_key}"
net:
  transport: ${transport}
  dns: "${OLCRTC_DNS:-8.8.8.8:53}"
data: data
debug: true
EOF
    write_transport_block "${transport}" "${tmp_cfg}"

    log "    [validate] provider=${provider}  transport=${transport}"
    log "    [validate] room_id=${room_id}"
    log "    [validate] config=${tmp_cfg}"
    log "    [validate] log=${tmp_log}"
    log "    [validate] timeout=${VALIDATE_WAIT}s"

    # ── Launch ──
    "${OLCRTC_BIN}" "${tmp_cfg}" > "${tmp_log}" 2>&1 &
    pid=$!
    log "    [validate] launched pid=${pid}"

    # ── Poll ──
    while (( elapsed < VALIDATE_WAIT )); do
        sleep 1
        elapsed=$((elapsed + 1))

        # Process died?
        if ! kill -0 "${pid}" 2>/dev/null; then
            wait "${pid}" 2>/dev/null
            local rc=$?
            log "    [validate] ⚠ process exited at ${elapsed}s, exit_code=${rc}"
            [[ ${rc} -eq 0 ]] && success=true
            break
        fi

        # Fatal errors → stop early
        if grep -qiE 'panic|fatal|failed to (connect|create|join|dial)|connection refused|no such host|unreachable|handshake failed|tls|certificate' "${tmp_log}" 2>/dev/null; then
            log "    [validate] ⚠ fatal error in log at ${elapsed}s"
            break
        fi

        # Positive indicators (broad patterns)
        if grep -qiE 'room.*(created|ready|started|opened)|connected|listening|initialized|waiting|participant|joined|server.*(start|run)|offer|answer|ice.*(gather|candidate)|sdp' "${tmp_log}" 2>/dev/null; then
            log "    [validate] ✓ success indicator at ${elapsed}s"
            success=true
            break
        fi

        # Progress tick
        (( elapsed % 3 == 0 )) && log "    [validate] ... waiting (${elapsed}/${VALIDATE_WAIT}s), process alive"
    done

    # Process survived full wait with no errors → success
    if (( elapsed >= VALIDATE_WAIT )) && kill -0 "${pid}" 2>/dev/null; then
        if ! grep -qiE 'panic|fatal|failed|error|refused|timeout' "${tmp_log}" 2>/dev/null; then
            log "    [validate] ✓ process alive after ${VALIDATE_WAIT}s, no errors → success"
            success=true
        else
            log "    [validate] ⚠ process alive but errors found in log"
        fi
    fi

    # ── Show last log lines ──
    echo ""
    if [[ "${success}" == "true" ]]; then
        log "    [validate] ✓✓✓ SUCCESS ✓✓✓  (last 8 lines of olcrtc log):"
    else
        log "    [validate] ✗✗✗ FAILED ✗✗✗  (last 8 lines of olcrtc log):"
    fi
    tail -8 "${tmp_log}" 2>/dev/null | while IFS= read -r line; do
        echo "    │ ${line}"
    done
    echo ""

    # ── Save failed log for debugging ──
    if [[ "${success}" != "true" ]]; then
        local failed_log="${LOG_DIR:-/opt/olcrtc/logs}/validate-failed-${provider}-$(date +%Y%m%d-%H%M%S).log"
        cp "${tmp_log}" "${failed_log}" 2>/dev/null
        log "    [validate] full log saved → ${failed_log}"
    fi

    # ── Cleanup ──
    kill "${pid}" 2>/dev/null
    wait "${pid}" 2>/dev/null
    rm -f "${tmp_cfg}" "${tmp_log}"

    [[ "${success}" == "true" ]]
}

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1 — Ping pre-filter
# ──────────────────────────────────────────────────────────────────────────────
log "Step 1/3: Ping pre-filter (${#JITSI_INSTANCES[@]} Jitsi hosts)..."

declare -a REACHABLE_HOSTS=()
declare -a REACHABLE_LATENCY=()

for instance in "${JITSI_INSTANCES[@]}"; do
    printf "  %-40s" "${instance}"
    lat=$(measure_latency_us "${instance}")
    if [[ -n "${lat}" && "${lat}" -gt 0 ]] 2>/dev/null; then
        printf " → %s ms\n" "$((lat / 1000))"
        REACHABLE_HOSTS+=("${instance}")
        REACHABLE_LATENCY+=("${lat}")
    else
        printf " → unreachable\n"
    fi
done
echo ""

# Sort by latency
if (( ${#REACHABLE_HOSTS[@]} > 1 )); then
    for (( i=1; i<${#REACHABLE_HOSTS[@]}; i++ )); do
        lh="${REACHABLE_HOSTS[$i]}"; ll="${REACHABLE_LATENCY[$i]}"
        j=$((i - 1))
        while (( j >= 0 )) && (( REACHABLE_LATENCY[j] > ll )); do
            REACHABLE_HOSTS[$((j+1))]="${REACHABLE_HOSTS[$j]}"
            REACHABLE_LATENCY[$((j+1))]="${REACHABLE_LATENCY[$j]}"
            j=$((j - 1))
        done
        REACHABLE_HOSTS[$((j+1))]="${lh}"; REACHABLE_LATENCY[$((j+1))]="${ll}"
    done
fi

log "Reachable: ${#REACHABLE_HOSTS[@]} / ${#JITSI_INSTANCES[@]}"
echo ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2 — Real validation via olcrtc
# ──────────────────────────────────────────────────────────────────────────────
log "Step 2/3: Real validation via olcrtc (top ${MAX_VALIDATE_CANDIDATES} Jitsi)..."
echo ""

SELECTED_PROVIDER=""
SELECTED_TRANSPORT=""
SELECTED_INSTANCE=""
SELECTED_ROOM_ID=""
SELECTED_FLAG="🏳️"

# 2a. Jitsi
limit=$(( ${#REACHABLE_HOSTS[@]} < MAX_VALIDATE_CANDIDATES ? ${#REACHABLE_HOSTS[@]} : MAX_VALIDATE_CANDIDATES ))
for (( i=0; i<limit; i++ )); do
    inst="${REACHABLE_HOSTS[$i]}"
    lat_ms=$(( REACHABLE_LATENCY[i] / 1000 ))
    log "── Jitsi candidate ${i}: ${inst} (${lat_ms} ms) ──"

    if validate_with_olcrtc "jitsi" "datachannel" "${inst}"; then
        SELECTED_PROVIDER="jitsi"
        SELECTED_TRANSPORT="datachannel"
        SELECTED_INSTANCE="${inst}"
        SELECTED_ROOM_ID=""
        SELECTED_FLAG=$(get_flag_for_host "${inst}")
        log "► Jitsi selected: ${inst}"
        break
    else
        log "► Jitsi ${inst} failed, trying next..."
    fi
    echo ""
done

# 2b. Fallback: other providers
if [[ -z "${SELECTED_PROVIDER}" ]]; then
    echo ""
    log "No Jitsi passed. Trying other providers..."
    echo ""
    for entry in "${OTHER_PROVIDERS[@]}"; do
        IFS=':' read -r pname phost ptransport <<< "${entry}"
        log "── ${pname} / ${ptransport} / ${phost} ──"

        if check_http "${phost}" && validate_with_olcrtc "${pname}" "${ptransport}" "${phost}"; then
            SELECTED_PROVIDER="${pname}"
            SELECTED_TRANSPORT="${ptransport}"
            SELECTED_INSTANCE="${phost}"
            SELECTED_ROOM_ID=""
            SELECTED_FLAG=$(get_flag_for_host "${phost}")
            log "► ${pname} selected"
            break
        else
            log "► ${pname} failed"
        fi
        echo ""
    done
fi

# 2c. TEST_ALL_PROVIDERS
if [[ "${OLCRTC_TEST_ALL_PROVIDERS:-false}" == "true" ]]; then
    echo ""
    log "OLCRTC_TEST_ALL_PROVIDERS=true → diagnostics for remaining providers..."
    echo ""
    for entry in "${OTHER_PROVIDERS[@]}"; do
        IFS=':' read -r pname phost ptransport <<< "${entry}"
        if [[ "${SELECTED_PROVIDER}" == "${pname}" ]]; then
            log "── ${pname}: already selected, skip ──"
            continue
        fi
        log "── ${pname} / ${ptransport} / ${phost} (diagnostics) ──"
        if check_http "${phost}" && validate_with_olcrtc "${pname}" "${ptransport}" "${phost}"; then
            log "► ${pname}: ✓ WORKS"
        else
            log "► ${pname}: ✗ DOES NOT WORK"
        fi
        echo ""
    done
fi

# 2d. Last resort
if [[ -z "${SELECTED_PROVIDER}" ]]; then
    warn "All providers failed! Using telemost as last resort."
    SELECTED_PROVIDER="telemost"
    SELECTED_TRANSPORT="vp8channel"
    SELECTED_INSTANCE="telemost.yandex.ru"
    SELECTED_ROOM_ID=""
    SELECTED_FLAG=$(get_flag_for_host "telemost.yandex.ru")
fi

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3 — Subscription name
# ──────────────────────────────────────────────────────────────────────────────
HOST_LABEL=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "olcrtc-node")
SUBSCRIPTION_NAME="${SELECTED_FLAG} | ${SELECTED_PROVIDER} | ${SELECTED_TRANSPORT} / ${HOST_LABEL}"

echo ""
log "Step 3/3: Subscription → ${SUBSCRIPTION_NAME}"
echo ""

export SELECTED_PROVIDER SELECTED_TRANSPORT SELECTED_INSTANCE SELECTED_ROOM_ID
export SELECTED_FLAG SUBSCRIPTION_NAME HOST_LABEL
