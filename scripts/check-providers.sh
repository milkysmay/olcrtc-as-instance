#!/usr/bin/env bash
# Phase 2: Ping all Jitsi instances, select lowest latency

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

measure_latency() {
    local host="$1" latency=""
    if command -v ping &>/dev/null; then
        latency=$(ping -c "${PING_COUNT}" -W "${PING_TIMEOUT}" "${host}" 2>/dev/null \
            | grep -oP 'time=\K[0-9.]+' | sort -n | head -1)
    fi
    if [[ -z "${latency}" ]]; then
        latency=$(curl -o /dev/null -s -w '%{time_connect}' \
            --connect-timeout "${CURL_TIMEOUT}" "https://${host}/" 2>/dev/null || echo "")
        if [[ -n "${latency}" && "${latency}" != "0.000000" ]]; then
            latency=$(echo "${latency} * 1000" | bc 2>/dev/null || echo "")
        else
            latency=""
        fi
    fi
    echo "${latency}"
}

check_http() {
    local code
    code=$(curl -o /dev/null -s -w '%{http_code}' \
        --connect-timeout "${CURL_TIMEOUT}" "https://$1/" 2>/dev/null || echo "000")
    [[ "${code}" != "000" ]]
}

log "Checking Jitsi instances (${#JITSI_INSTANCES[@]} hosts)..."
BEST_INSTANCE=""; BEST_LATENCY=999999; REACHABLE_COUNT=0

for instance in "${JITSI_INSTANCES[@]}"; do
    printf "  %-40s" "${instance}"
    latency=$(measure_latency "${instance}")
    if [[ -n "${latency}" ]]; then
        printf " → %s ms\n" "${latency%%.*}"
        REACHABLE_COUNT=$((REACHABLE_COUNT + 1))
        is_better=$(echo "${latency} < ${BEST_LATENCY}" | bc 2>/dev/null || echo "0")
        if [[ "${is_better}" == "1" ]]; then
            BEST_LATENCY="${latency}"; BEST_INSTANCE="${instance}"
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
    SELECTED_PROVIDER="jitsi"; SELECTED_TRANSPORT="datachannel"
    SELECTED_INSTANCE="${BEST_INSTANCE}"; SELECTED_ROOM_ID=""
    log "Best Jitsi instance: ${BEST_INSTANCE} (${BEST_LATENCY%%.*} ms)"
    log "Selected: jitsi + datachannel (recommended combination)"
else
    warn "No Jitsi instance reachable! Falling back to telemost + vp8channel"
    SELECTED_PROVIDER="telemost"; SELECTED_TRANSPORT="vp8channel"
    SELECTED_INSTANCE=""; SELECTED_ROOM_ID=""
fi

export SELECTED_PROVIDER SELECTED_TRANSPORT SELECTED_INSTANCE SELECTED_ROOM_ID
