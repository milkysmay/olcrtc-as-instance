#!/usr/bin/env bash
# Safe room names — NO words: proxy, vpn, olcrtc, tunnel, socks, webrtc, crypto...

if [[ "${1:-}" == "--dump-words" ]]; then
    cat <<'WORDS'
morning sunny quiet gentle bright calm warm cool soft clear
golden silver amber coral ivory jade ruby pearl azure emerald
river garden forest meadow ocean mountain valley harbor island prairie
maple cedar willow birch aspen linden rowan hawthorn juniper magnolia
sparrow robin finch heron crane swift wren lark dove falcon
autumn spring winter summer dawn dusk twilight sunrise sunset noon
WORDS
    exit 0
fi

ADJECTIVES=(
    morning sunny quiet gentle bright calm warm cool soft clear
    golden silver amber coral ivory jade ruby pearl azure emerald
)
NOUNS=(
    river garden forest meadow ocean mountain valley harbor island prairie
    maple cedar willow birch aspen linden rowan hawthorn juniper magnolia
    sparrow robin finch heron crane swift wren lark dove falcon
    autumn spring winter summer dawn dusk twilight sunrise sunset noon
)

adj="${ADJECTIVES[$((RANDOM % ${#ADJECTIVES[@]}))]}"
noun="${NOUNS[$((RANDOM % ${#NOUNS[@]}))]}"
num=$((RANDOM % 900 + 100))
echo "${adj}-${noun}-${num}"
