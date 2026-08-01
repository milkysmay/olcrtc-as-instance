#!/usr/bin/env bash
# Phase 2: Ping all Jitsi instances, select lowest latency
# NOTE: no bc dependency — all comparisons use integer arithmetic (ms × 1000)

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
    "telemost:telemost.yandex.ru"
    "wbstream:stream.wb.ru"
)

PING_TIMEOUT=3; PING_COUNT=2; CURL_TIMEOUT=5

# Returns latency as INTEGER microseconds (ms × 1000), or empty on failure
measure_latency() {
    local host="$1" latency_ms=""

    # Try ICMP ping first
    if command -v ping &>/dev/null; then
        latency_ms=$(ping -c "${PING_COUNT}" -W "${PING_TIMEOUT}" "${host}" 2>/dev/null \
            | grep -oP 'time=\K[0-9.]+' | sort -n | head -1)
    fi

    # Fallback: curl TCP connect time
    if [[ -z "${latency_ms}" ]]; then
        local connect_s
        connect_s=$(curl -o /dev/null -s -w '%{time_connect}' \
            --connect-timeout "${CURL_TIMEOUT}" "https://${host}/" 2>/dev/null || echo "")
        if [[ -n "${connect_s}" && "${connect_s}" != "0.000000" ]]; then
            # Convert seconds → milliseconds (integer)
            latency_ms=$(awk "BEGIN {printf \"%.0f\", ${connect_s} * 1000}" 2>/dev/null || echo "")
        fi
    fi

    # Convert ms (possibly float) → integer microseconds for safe bash comparison
    if [[ -n "${latency_ms}" ]]; then
        awk "BEGIN {printf \"%.0f\", ${latency_ms} * 1000}" 2>/dev/null || echo ""
    fi
}

check_http() {
    local code
    code=$(curl -o /dev/null -s -w '%{http_code}' \
        --connect-timeout "${CURL_TIMEOUT}" "https://$1/" 2>/dev/null || echo "000")
    [[ "${code}" != "000" ]]
}

log "Checking Jitsi instances (${#JITSI_INSTANCES[@]} hosts)..."
BEST_INSTANCE=""
BEST_LATENCY_US=999999999   # integer microseconds
REACHABLE_COUNT=0

for instance in "${JITSI_INSTANCES[@]}"; do
    printf "  %-40s" "${instance}"
    latency_us=$(measure_latency "${instance}")

    if [[ -n "${latency_us}" && "${latency_us}" -gt 0 ]] 2>/dev/null; then
        latency_display=$((latency_us / 1000))
        printf " → %s ms\n" "${latency_display}"
        REACHABLE_COUNT=$((REACHABLE_COUNT + 1))

        # Pure bash integer comparison — no bc needed
        if (( latency_us < BEST_LATENCY_US )); then
            BEST_LATENCY_US="${latency_us}"
            BEST_INSTANCE="${instance}"
        fi
    else
        printf " → unreachable\n"
    fi
done
echo ""

log "Checking other providers..."
for entry in "${OTHER_PROVIDERS[@]}"; do
    pname="${entry%%:*}"; phost="${entry#*:}"
    printf "  %-40s" "${pname} (${phost})"
    if check_http "${phost}"; then printf " → reachable\n"; else printf " → unreachable\n"; fi
done
echo ""

if [[ -n "${BEST_INSTANCE}" ]]; then
    SELECTED_PROVIDER="jitsi"
    SELECTED_TRANSPORT="datachannel"
    SELECTED_INSTANCE="${BEST_INSTANCE}"
    SELECTED_ROOM_ID=""
    best_ms=$((BEST_LATENCY_US / 1000))
    log "Best Jitsi instance: ${BEST_INSTANCE} (${best_ms} ms)"
    log "Selected: jitsi + datachannel (recommended)"
else
    warn "No Jitsi instance reachable! Falling back to telemost + vp8channel"
    SELECTED_PROVIDER="telemost"
    SELECTED_TRANSPORT="vp8channel"
    SELECTED_INSTANCE=""
    SELECTED_ROOM_ID=""
fi

export SELECTED_PROVIDER SELECTED_TRANSPORT SELECTED_INSTANCE SELECTED_ROOM_ID
