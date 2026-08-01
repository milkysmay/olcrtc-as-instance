#!/usr/bin/env bash
# Phase 2: Validate providers by ACTUALLY launching olcrtc and joining a room.
#   Step 1 — quick ping pre-filter
#   Step 2 — real validation via olcrtc (top-N jitsi, then others)
#   Step 3 — detect country flag + build subscription name
#
# OLCRTC_TEST_ALL_PROVIDERS=true → also validate telemost/wbstream
#   even when jitsi already passed (diagnostics only, does NOT change selection).

OLCRTC_BIN="/usr/local/bin/olcrtc"

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

# provider:host:default_transport
OTHER_PROVIDERS=(
    "telemost:telemost.yandex.ru:vp8channel"
    "wbstream:stream.wb.ru:datachannel"
)

PING_TIMEOUT=3; PING_COUNT=2; CURL_TIMEOUT=5
VALIDATE_WAIT=6
MAX_VALIDATE_CANDIDATES=5

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

# Country code → flag emoji (python3 primary, bash printf fallback)
country_to_flag() {
    local cc="${1^^}"
    [[ ${#cc} -ne 2 ]] && { echo "🏳️"; return; }

    local flag=""
    flag=$(python3 -c "print(''.join(chr(0x1F1E6+ord(c)-65) for c in '${cc}'))" 2>/dev/null)

    if [[ -z "${flag}" ]]; then
        local i c ascii code hex
        for (( i=0; i<2; i++ )); do
            c="${cc:$i:1}"
            ascii=$(printf '%d' "'${c}")
            code=$(( 0x1F1E6 + ascii - 65 ))
            hex=$(printf '%08x' "${code}")
            flag+="$(printf "\\U${hex}" 2>/dev/null)"
        done
    fi

    [[ -n "${flag}" ]] && echo "${flag}" || echo "🏳️"
}

get_flag_for_host() {
    local host="$1" ip cc=""
    ip=$(resolve_ip "${host}")
    [[ -z "${ip}" ]] && { echo "🏳️"; return; }

    cc=$(curl -s --connect-timeout 3 \
        "http://ip-api.com/json/${ip}?fields=countryCode" 2>/dev/null \
        | grep -oP '"countryCode"\s*:\s*"\K[A-Z]{2}')

    [[ -z "${cc}" ]] && cc=$(curl -s --connect-timeout 3 \
        "https://ipwho.is/${ip}" 2>/dev/null \
        | grep -oP '"country_code"\s*:\s*"\K[A-Z]{2}')

    [[ -n "${cc}" ]] && country_to_flag "${cc}" || echo "🏳️"
}

# ──────────────────────────────────────────────────────────────────────────────
# Real validation: launch olcrtc, try to create a room
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
  dns: "8.8.8.8:53"
data: data
debug: true
EOF

    case "${transport}" in
        vp8channel)   printf '\nvp8:\n  fps: 30\n  batch_size: 64\n' >> "${tmp_cfg}" ;;
        seichannel)   printf '\nsei:\n  fps: 30\n  batch_size: 64\n  fragment_size: 900\n  ack_timeout_ms: 2000\n' >> "${tmp_cfg}" ;;
        videochannel) printf '\nvideo:\n  codec: qrcode\n  width: 1080\n  height: 1080\n  fps: 30\n  bitrate: "5000k"\n  hw: none\n' >> "${tmp_cfg}" ;;
    esac

    "${OLCRTC_BIN}" "${tmp_cfg}" > "${tmp_log}" 2>&1 &
    pid=$!

    while (( elapsed < VALIDATE_WAIT )); do
        sleep 1
        elapsed=$((elapsed + 1))

        if ! kill -0 "${pid}" 2>/dev/null; then
            wait "${pid}" 2>/dev/null
            [[ $? -eq 0 ]] && success=true
            break
        fi

        if grep -qiE 'room.*(created|ready|started)|connected|listening|initialized' "${tmp_log}" 2>/dev/null; then
            success=true
            break
        fi

        if grep -qiE 'panic|fatal|failed to (connect|create|join|dial)|connection refused|no such host|unreachable' "${tmp_log}" 2>/dev/null; then
            break
        fi
    done

    if (( elapsed >= VALIDATE_WAIT )) && kill -0 "${pid}" 2>/dev/null; then
        if ! grep -qiE 'panic|fatal|failed|error|refused' "${tmp_log}" 2>/dev/null; then
            success=true
        fi
    fi

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

# Sort by latency (insertion sort)
if (( ${#REACHABLE_HOSTS[@]} > 1 )); then
    for (( i=1; i<${#REACHABLE_HOSTS[@]}; i++ )); do
        lh="${REACHABLE_HOSTS[$i]}"
        ll="${REACHABLE_LATENCY[$i]}"
        j=$((i - 1))
        while (( j >= 0 )) && (( REACHABLE_LATENCY[j] > ll )); do
            REACHABLE_HOSTS[$((j+1))]="${REACHABLE_HOSTS[$j]}"
            REACHABLE_LATENCY[$((j+1))]="${REACHABLE_LATENCY[$j]}"
            j=$((j - 1))
        done
        REACHABLE_HOSTS[$((j+1))]="${lh}"
        REACHABLE_LATENCY[$((j+1))]="${ll}"
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

# 2a. Jitsi candidates
limit=$(( ${#REACHABLE_HOSTS[@]} < MAX_VALIDATE_CANDIDATES ? ${#REACHABLE_HOSTS[@]} : MAX_VALIDATE_CANDIDATES ))
for (( i=0; i<limit; i++ )); do
    inst="${REACHABLE_HOSTS[$i]}"
    lat_ms=$(( REACHABLE_LATENCY[i] / 1000 ))
    printf "  ▸ jitsi / datachannel / %-35s (%s ms) ... " "${inst}" "${lat_ms}"

    if validate_with_olcrtc "jitsi" "datachannel" "${inst}"; then
        echo "✓ ROOM CREATED"
        SELECTED_PROVIDER="jitsi"
        SELECTED_TRANSPORT="datachannel"
        SELECTED_INSTANCE="${inst}"
        SELECTED_ROOM_ID=""
        SELECTED_FLAG=$(get_flag_for_host "${inst}")
        break
    else
        echo "✗ FAILED"
    fi
done

# 2b. Fallback: other providers (only if no Jitsi passed)
if [[ -z "${SELECTED_PROVIDER}" ]]; then
    echo ""
    log "No Jitsi passed. Trying other providers..."
    for entry in "${OTHER_PROVIDERS[@]}"; do
        IFS=':' read -r pname phost ptransport <<< "${entry}"
        printf "  ▸ %s / %s / %-35s ... " "${pname}" "${ptransport}" "${phost}"

        if check_http "${phost}" && validate_with_olcrtc "${pname}" "${ptransport}" "${phost}"; then
            echo "✓ ROOM CREATED"
            SELECTED_PROVIDER="${pname}"
            SELECTED_TRANSPORT="${ptransport}"
            SELECTED_INSTANCE="${phost}"
            SELECTED_ROOM_ID=""
            SELECTED_FLAG=$(get_flag_for_host "${phost}")
            break
        else
            echo "✗ FAILED"
        fi
    done
fi

# 2c. TEST_ALL_PROVIDERS: validate remaining providers for diagnostics
if [[ "${OLCRTC_TEST_ALL_PROVIDERS:-false}" == "true" ]]; then
    echo ""
    log "OLCRTC_TEST_ALL_PROVIDERS=true → validating remaining providers (diagnostics)..."
    for entry in "${OTHER_PROVIDERS[@]}"; do
        IFS=':' read -r pname phost ptransport <<< "${entry}"

        # Skip the one already selected
        if [[ "${SELECTED_PROVIDER}" == "${pname}" ]]; then
            printf "  ▸ %s / %s / %-35s ... " "${pname}" "${ptransport}" "${phost}"
            echo "⊘ ALREADY SELECTED"
            continue
        fi

        printf "  ▸ %s / %s / %-35s ... " "${pname}" "${ptransport}" "${phost}"
        if check_http "${phost}" && validate_with_olcrtc "${pname}" "${ptransport}" "${phost}"; then
            echo "✓ ROOM CREATED"
        else
            echo "✗ FAILED"
        fi
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
