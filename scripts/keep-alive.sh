#!/usr/bin/env bash
set -euo pipefail

poll_seconds=30

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  keep-alive --member <Artanis|Argus|Aegis> [--display]

Keeps this Mac awake while the member's processes run, without changing pmset settings.

Members:
  Artanis  terminal codex sessions and the Codex desktop app (ChatGPT.app or Codex.app)
  Argus    terminal claude sessions
  Aegis    terminal copilot sessions (copilot or gh copilot)

Options:
  --display  Also keep the display on (no screen off / lock). Default lets the display sleep;
             the member keeps working behind the locked screen.

Behavior:
  - Holds caffeinate -ims (plus -d with --display) while any member process is alive.
  - Re-scans every 30s, so new sessions of the member are picked up.
  - Releases automatically when no member process remains, or on Ctrl+C.

Notes:
  - Closing the MacBook lid still sleeps the Mac (unless in clamshell mode with an external display).
  - System-sleep prevention (-s) only applies on AC power.
EOF
}

member_processes() {
  local member="$1" pid tty comm name
  while read -r pid tty comm; do
    name="${comm##*/}"
    case "$member" in
      artanis)
        if [[ "$tty" != "??" && "$name" == "codex" ]]; then
          printf '%s\tterminal codex (%s)\n' "$pid" "$tty"
        fi
        case "$comm" in
          /Applications/ChatGPT.app/Contents/MacOS/ChatGPT | /Applications/Codex.app/Contents/MacOS/Codex)
            printf '%s\tCodex app (%s)\n' "$pid" "${comm#/Applications/}"
            ;;
        esac
        ;;
      argus)
        if [[ "$tty" != "??" && "$name" == "claude" ]]; then
          printf '%s\tterminal claude (%s)\n' "$pid" "$tty"
        fi
        ;;
      aegis)
        [[ "$tty" != "??" ]] || continue
        if [[ "$name" == "copilot" ]] ||
          { [[ "$name" == "gh" ]] && ps -o args= -p "$pid" 2>/dev/null | grep -q '^gh copilot'; }; then
          printf '%s\tterminal copilot (%s)\n' "$pid" "$tty"
        fi
        ;;
    esac
  done < <(ps -axo pid=,tty=,comm=)
}

member=""
keep_display=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --member)
      [[ $# -ge 2 ]] || die "--member requires a value."
      member="$2"
      shift 2
      ;;
    --display)
      keep_display=true
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      die "Unknown argument '$1'."
      ;;
  esac
done

[[ -n "$member" ]] || { usage >&2; die "--member is required."; }
[[ "$(uname -s)" == "Darwin" ]] || die "keep-alive requires macOS caffeinate."

member_key="$(printf '%s' "$member" | tr '[:upper:]' '[:lower:]')"
case "$member_key" in
  artanis | argus | aegis) ;;
  *) die "Unsupported member '$member'. Use Artanis, Argus, or Aegis." ;;
esac
display_name="$(printf '%s' "${member_key:0:1}" | tr '[:lower:]' '[:upper:]')${member_key:1}"

found="$(member_processes "$member_key")"
[[ -n "$found" ]] || die "No running $display_name process found. Start $display_name first."

echo "Keeping this Mac awake for $display_name:"
printf '%s\n' "$found" | while IFS=$'\t' read -r pid label; do
  echo "  pid $pid  $label"
done

if ! pmset -g batt 2>/dev/null | grep -q "AC Power"; then
  echo "Warning: on battery; only idle sleep is prevented. Plug in for full protection."
fi
echo "Keep the lid open. Press Ctrl+C to release."

caffeinate_flags="-ims"
[[ "$keep_display" == true ]] && caffeinate_flags="-dims"

caffeinate "$caffeinate_flags" &
caffeinate_pid=$!
trap 'kill "$caffeinate_pid" 2>/dev/null || true' EXIT
trap 'echo; echo "Released."; exit 0' INT TERM

while true; do
  sleep "$poll_seconds" &
  wait $! || true
  kill -0 "$caffeinate_pid" 2>/dev/null || die "caffeinate stopped unexpectedly."
  if [[ -z "$(member_processes "$member_key")" ]]; then
    echo "$display_name has no running processes; released."
    exit 0
  fi
done
