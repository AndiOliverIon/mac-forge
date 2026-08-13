#!/usr/bin/env bash
set -euo pipefail

#######################################
# net - show active network connections by friendly name, pick one,
#       and run an Apple networkQuality speed test bound to that interface.
#######################################

die() {
  echo "✖ $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

[[ "$(uname -s)" == "Darwin" ]] || die "net currently supports macOS only (uses networkQuality)."

require_cmd networkQuality
require_cmd networksetup
require_cmd ipconfig
require_cmd fzf
require_cmd jq
require_cmd route

#######################################
# Enumerate active services (friendly name + device + IP)
#######################################
# Map device -> friendly service name from the service order list.
service_map="$(
  networksetup -listnetworkserviceorder | awk '
    /^\([0-9]+\)/ { name=$0; sub(/^\([0-9]+\) /, "", name) }
    /Hardware Port:/ {
      line=$0
      sub(/.*Device: /, "", line)
      sub(/\).*/, "", line)
      dev=line
      if (dev != "") print dev "\t" name
    }
  '
)"

default_if="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"

# Build active list: only services whose device currently has an IPv4 address.
active=""
while IFS=$'\t' read -r dev name; do
  [[ -n "$dev" ]] || continue
  ip="$(ipconfig getifaddr "$dev" 2>/dev/null || true)"
  [[ -n "$ip" ]] || continue

  extra=""
  if [[ "$dev" == en* ]]; then
    ssid="$(networksetup -getairportnetwork "$dev" 2>/dev/null | sed -n 's/^Current Wi-Fi Network: //p')"
    [[ -n "$ssid" ]] && extra=" [$ssid]"
  fi
  marker=""
  [[ "$dev" == "$default_if" ]] && marker=" *"

  # display<TAB>device
  printf -v row '%-26s %-15s %-8s%s%s\t%s' "$name$extra" "$ip" "$dev" "$marker" "" "$dev"
  active+="$row"$'\n'
done <<< "$service_map"

[[ -n "${active//[$'\n']/}" ]] || die "No active network connections found."

#######################################
# Pick a connection (optional arg pre-filters by name)
#######################################
query="${1:-}"
selection="$(
  printf '%s' "$active" |
    fzf --prompt="net > " --height=40% --reverse --with-nth=1 --delimiter=$'\t' \
        --header="active connections ( * = default route )   select one to speed-test" \
        ${query:+--query "$query"}
)" || exit 0

[[ -n "${selection:-}" ]] || exit 0

dev="${selection##*$'\t'}"
label="$(printf '%s' "${selection%%$'\t'*}" | sed 's/[[:space:]]*$//')"

#######################################
# Run the speed test bound to the chosen interface
#######################################
echo "Running speed test on: $label"
echo "Interface: $dev   (this takes ~15-25s, testing download + upload)..."
echo

tmp="$(mktemp -t net-speedtest.XXXXXX)"
trap 'rm -f "$tmp"' EXIT

if ! networkQuality -c -I "$dev" >"$tmp" 2>/dev/null; then
  die "Speed test failed on $dev. Is this interface connected to the internet?"
fi

# networkQuality throughput is in bits/sec.
read -r dl ul rtt rpm endpoint < <(
  jq -r '[
    (.dl_throughput // 0),
    (.ul_throughput // 0),
    (.base_rtt // 0),
    (.responsiveness // 0),
    (.test_endpoint // "n/a")
  ] | @tsv' "$tmp" | tr '\t' ' '
)

fmt_mbps() { awk -v b="$1" 'BEGIN { printf "%.1f", b/1000000 }'; }
fmt_ms()   { awk -v v="$1" 'BEGIN { printf "%.0f", v }'; }

echo "──────────────────────────────────────────────"
echo "  Connection : $label"
echo "  Endpoint   : $endpoint"
echo "  Download   : $(fmt_mbps "$dl") Mbps"
echo "  Upload     : $(fmt_mbps "$ul") Mbps"
echo "  Latency    : $(fmt_ms "$rtt") ms (base RTT)"
echo "  Respons.   : $(fmt_ms "$rpm") RPM"
echo "──────────────────────────────────────────────"
