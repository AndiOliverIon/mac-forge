#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="${FORGE_ROOT:-$(cd -- "$SCRIPT_DIR/../.." && pwd)}"
STATIONS_CONFIG="${FORGE_STATIONS_CONFIG:-$FORGE_ROOT/configs/stations.json}"

cpu_effort_line() {
  top -bn1 2>/dev/null | awk -F ', *' '/^%Cpu/ {
    user=$1
    sys=$2
    gsub(/^[^0-9.]*/, "", user)
    gsub(/[^0-9.].*$/, "", user)
    gsub(/^[^0-9.]*/, "", sys)
    gsub(/[^0-9.].*$/, "", sys)
    if (user != "" && sys != "") {
      printf "%s%% user, %s%% sys", user, sys
      exit
    }
  }'
}

friendly_uptime() {
  uptime -p | sed -E 's/^up //; s/, ([0-9]+ minutes?)$/ \1/'
}

cpu_model_line() {
  awk -F: '/^model name[[:space:]]*:/ {
    value=$2
    sub(/^[[:space:]]+/, "", value)
    print value
    exit
  }' /proc/cpuinfo 2>/dev/null
}

cpu_temp_line() {
  local temp_raw

  if [[ -r /sys/class/thermal/thermal_zone0/temp ]]; then
    temp_raw="$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || true)"
    if [[ "$temp_raw" =~ ^[0-9]+$ ]]; then
      awk -v value="$temp_raw" 'BEGIN { printf "%.1f C", value / 1000 }'
      return 0
    fi
  fi

  if command -v sensors >/dev/null 2>&1; then
    sensors 2>/dev/null | awk '
      /\+([0-9]+(\.[0-9]+)?)°C/ {
        match($0, /\+([0-9]+(\.[0-9]+)?)°C/, parts)
        if (parts[1] != "") {
          printf "%s C", parts[1]
          exit
        }
      }'
    return 0
  fi

  printf 'Unavailable'
}

storage_lines() {
  local path="${1:-/}"

  df -hT "$path" | awk 'NR==2 {print $1 "\n" $2 "\n" $3 "\n" $5 "\n" $4 "\n" $6}'
}

memory_lines() {
  # total used available free cache
  free -h 2>/dev/null | awk '/^Mem:/ {print $2 "\n" $3 "\n" $7 "\n" $4 "\n" $6}'
}

memory_percent() {
  free -k 2>/dev/null | awk '/^Mem:/ { if ($2 > 0) printf "%.0f", $3 / $2 * 100; else printf "0" }'
}

create_history_log() {
  local downloads_dir="$HOME/Downloads"
  local today
  local iteration=1
  local existing_file
  local existing_iteration
  local history_file

  if ! mkdir -p "$downloads_dir"; then
    printf 'Unable to create Downloads directory: %s\n' "$downloads_dir" >&2
    return 1
  fi
  today="$(date '+%Y-%m-%d')"
  for existing_file in "$downloads_dir"/inf-history-"$today"-*.tsv; do
    [[ -e "$existing_file" ]] || continue
    existing_iteration="${existing_file%.tsv}"
    existing_iteration="${existing_iteration##*-}"
    if [[ "$existing_iteration" =~ ^[0-9]+$ ]] && (( 10#$existing_iteration >= iteration )); then
      iteration=$((10#$existing_iteration + 1))
    fi
  done

  while true; do
    history_file="$(printf '%s/inf-history-%s-%02d.tsv' "$downloads_dir" "$today" "$iteration")"
    if (
      set -o noclobber
      printf 'timestamp\tcpu_user_percent\tcpu_system_percent\tmemory_used_kib\tmemory_total_kib\tmemory_used_percent\ttemperature_c\troot_used_kib\troot_total_kib\troot_used_percent\tdata_used_kib\tdata_total_kib\tdata_used_percent\n' \
        > "$history_file"
    ) 2>/dev/null; then
      printf '%s' "$history_file"
      return
    fi
    if [[ -e "$history_file" ]]; then
      iteration=$((iteration + 1))
    else
      printf 'Unable to create info history log: %s\n' "$history_file" >&2
      return 1
    fi
  done
}

cpu_history_values() {
  top -bn1 2>/dev/null | awk -F ', *' '/^%Cpu/ {
    user=$1
    sys=$2
    gsub(/^[^0-9.]*/, "", user)
    gsub(/[^0-9.].*$/, "", user)
    gsub(/^[^0-9.]*/, "", sys)
    gsub(/[^0-9.].*$/, "", sys)
    if (user != "" && sys != "") {
      printf "%s %s", user, sys
      exit
    }
  }'
}

history_sample() {
  local cpu_user cpu_system
  local memory_total memory_used memory_used_percent
  local temperature
  local root_total root_used root_used_percent
  local data_total="Unavailable"
  local data_used="Unavailable"
  local data_used_percent="Unavailable"

  read -r cpu_user cpu_system < <(cpu_history_values || true)
  read -r memory_total memory_used memory_used_percent < <(
    free -k 2>/dev/null | awk '/^Mem:/ {
      percent = ($2 > 0) ? $3 / $2 * 100 : 0
      printf "%s %s %.1f", $2, $3, percent
    }'
  )
  temperature="$(cpu_temp_line || true)"
  temperature="${temperature% C}"
  read -r root_total root_used root_used_percent < <(
    df -Pk / 2>/dev/null | awk 'NR==2 {percent=$5; sub(/%$/, "", percent); print $2, $3, percent}'
  )

  if mountpoint -q /data; then
    read -r data_total data_used data_used_percent < <(
      df -Pk /data 2>/dev/null | awk 'NR==2 {percent=$5; sub(/%$/, "", percent); print $2, $3, percent}'
    )
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${cpu_user:-Unavailable}" \
    "${cpu_system:-Unavailable}" \
    "${memory_used:-Unavailable}" \
    "${memory_total:-Unavailable}" \
    "${memory_used_percent:-Unavailable}" \
    "${temperature:-Unavailable}" \
    "${root_used:-Unavailable}" \
    "${root_total:-Unavailable}" \
    "${root_used_percent:-Unavailable}" \
    "$data_used" \
    "$data_total" \
    "$data_used_percent"
}

meaningful_history_change() {
  local previous_sample="$1"
  local current_sample="$2"

  awk \
    -v previous="$previous_sample" \
    -v current="$current_sample" \
    -v cpu_delta="$HISTORY_CPU_DELTA_PERCENT" \
    -v memory_delta="$HISTORY_MEMORY_DELTA_PERCENT" \
    -v temperature_delta="$HISTORY_TEMPERATURE_DELTA_C" \
    -v storage_delta="$HISTORY_STORAGE_DELTA_KIB" '
    function numeric(value) {
      return value ~ /^-?[0-9]+([.][0-9]+)?$/
    }
    function changed_by(field_number, threshold, difference) {
      if (!numeric(before[field_number]) || !numeric(after[field_number])) {
        return before[field_number] != after[field_number]
      }
      difference = after[field_number] - before[field_number]
      if (difference < 0) difference = -difference
      return difference >= threshold
    }
    BEGIN {
      split(previous, before, "\t")
      split(current, after, "\t")

      if (changed_by(1, cpu_delta) || changed_by(2, cpu_delta)) exit 0
      if (numeric(before[1]) && numeric(before[2]) && numeric(after[1]) && numeric(after[2])) {
        difference = (after[1] + after[2]) - (before[1] + before[2])
        if (difference < 0) difference = -difference
        if (difference >= cpu_delta) exit 0
      }
      if (changed_by(5, memory_delta) || changed_by(6, temperature_delta)) exit 0
      if (changed_by(7, storage_delta) || changed_by(10, storage_delta)) exit 0
      if (before[4] != after[4] || before[8] != after[8] || before[11] != after[11]) exit 0
      exit 1
    }'
}

record_history_sample() {
  local history_file="$1"
  local sample="$2"
  local now

  now="$(date '+%s')"
  if (( HISTORY_LAST_EPOCH > 0 && now - HISTORY_LAST_EPOCH < HISTORY_MIN_INTERVAL_SECONDS )); then
    HISTORY_STATUS="waiting"
    return
  fi
  if [[ -n "$HISTORY_LAST_SAMPLE" ]] && ! meaningful_history_change "$HISTORY_LAST_SAMPLE" "$sample"; then
    HISTORY_STATUS="unchanged"
    return
  fi

  HISTORY_TIMESTAMP="$(date '+%Y-%m-%dT%H:%M:%S%z')"
  printf '%s\t%s\n' "$HISTORY_TIMESTAMP" "$sample" >> "$history_file"
  HISTORY_LAST_EPOCH="$now"
  HISTORY_LAST_SAMPLE="$sample"
  HISTORY_STATUS="recorded"
}

discover_station_agents() {
  local station_id

  command -v jq >/dev/null 2>&1 || return
  [[ -r "$STATIONS_CONFIG" ]] || return
  station_id="$(hostname -s 2>/dev/null | tr '[:upper:]' '[:lower:]')"
  jq -r --arg station_id "$station_id" '
    ([
      .stations[]
      | select(
          (([.id, .name] + (.identifiers.hostnames // []))
          | map(select(type == "string") | ascii_downcase)
          | index($station_id)) != null
        )
    ][0].agentRuntime.identities // [])[]
    | select((.id | type) == "string")
    | [
        .id,
        (.universeRoot // ""),
        (.tmuxSocket // .id),
        (.tmuxSession // .id)
      ]
    | @tsv
  ' "$STATIONS_CONFIG" 2>/dev/null || true
}

create_agent_history_log() {
  local system_history_file="$1"
  local history_dir="${system_history_file%/*}"
  local history_name="${system_history_file##*/}"
  local agent_history_file

  history_name="${history_name/inf-history-/inf-agents-}"
  agent_history_file="$history_dir/$history_name"
  if ! (
    set -o noclobber
    printf 'timestamp\tidentity\tstate\tcpu_core_percent\tcpu_system_percent\tmemory_rss_kib\tprocess_count\n' \
      > "$agent_history_file"
  ) 2>/dev/null; then
    printf 'Unable to create agent history log: %s\n' "$agent_history_file" >&2
    return 1
  fi
  printf '%s' "$agent_history_file"
}

logical_cpu_count() {
  getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1'
}

history_monitor_pids() {
  printf '%s' "$HISTORY_MONITOR_PID"
  LC_ALL=C ps -axo pid=,command= 2>/dev/null | awk -v current="$HISTORY_MONITOR_PID" '
    $1 != current && ($0 ~ /\/inf\.sh[[:space:]]+--cycle/ || $0 ~ /\/info\.sh[[:space:]]+--cycle/) {
      printf ",%s", $1
    }'
}

agent_process_metrics() {
  local tmux_socket="$1"
  local tmux_session="$2"
  local pane_pids
  local root_pids
  local monitor_pids

  if ! command -v tmux >/dev/null 2>&1 \
    || ! tmux -L "$tmux_socket" has-session -t "$tmux_session" 2>/dev/null; then
    printf 'inactive\t0.0\t0.0\t0\t0'
    return
  fi

  pane_pids="$(tmux -L "$tmux_socket" list-panes -s -t "$tmux_session" -F '#{pane_pid}' 2>/dev/null || true)"
  root_pids="${pane_pids//$'\n'/,}"
  monitor_pids="$(history_monitor_pids)"
  if [[ -z "$root_pids" ]]; then
    printf 'idle\t0.0\t0.0\t0\t0'
    return
  fi

  LC_ALL=C ps -axo pid=,ppid=,%cpu=,rss= 2>/dev/null | awk \
    -v roots="$root_pids" \
    -v exclude_roots="$monitor_pids" \
    -v logical_cpus="$HISTORY_LOGICAL_CPU_COUNT" '
    {
      process_count++
      pid[process_count] = $1
      parent[process_count] = $2
      cpu[process_count] = $3
      memory[process_count] = $4
    }
    END {
      root_count = split(roots, root, ",")
      for (i = 1; i <= root_count; i++) {
        if (root[i] != "") owned[root[i]] = 1
      }
      excluded_count = split(exclude_roots, excluded_root, ",")
      for (i = 1; i <= excluded_count; i++) {
        if (excluded_root[i] != "") excluded[excluded_root[i]] = 1
      }
      do {
        found = 0
        for (i = 1; i <= process_count; i++) {
          if (!owned[pid[i]] && owned[parent[i]]) {
            owned[pid[i]] = 1
            found = 1
          }
          if (!excluded[pid[i]] && excluded[parent[i]]) {
            excluded[pid[i]] = 1
            found = 1
          }
        }
      } while (found)

      for (i = 1; i <= process_count; i++) {
        if (owned[pid[i]] && !excluded[pid[i]]) {
          agent_processes++
          agent_cpu += cpu[i]
          agent_memory += memory[i]
        }
      }
      system_cpu = (logical_cpus > 0) ? agent_cpu / logical_cpus : 0
      state = (agent_cpu >= 1) ? "busy" : "idle"
      printf "%s\t%.1f\t%.1f\t%.0f\t%d", state, agent_cpu, system_cpu, agent_memory, agent_processes
    }'
}

record_agent_history_samples() {
  local agent_history_file="$1"
  local timestamp="$2"
  local identities="$3"
  local identity_id universe_root tmux_socket tmux_session metrics

  while IFS=$'\t' read -r identity_id universe_root tmux_socket tmux_session; do
    [[ -n "$identity_id" ]] || continue
    metrics="$(agent_process_metrics "$tmux_socket" "$tmux_session")"
    printf '%s\t%s\t%s\n' "$timestamp" "$identity_id" "$metrics" >> "$agent_history_file"
  done <<< "$identities"
}

battery_lines() {
  local battery
  local full_capacity
  local design_capacity
  local health_state

  for battery in /sys/class/power_supply/BAT*; do
    [[ -d "$battery" ]] || continue
    printf '%s\n' "$(cat "$battery/capacity" 2>/dev/null || printf 'unknown')"
    printf '%s\n' "$(cat "$battery/status" 2>/dev/null || printf 'unknown')"
    if [[ -r "$battery/cycle_count" ]]; then
      cat "$battery/cycle_count" 2>/dev/null || printf 'unknown\n'
    else
      printf 'Unavailable\n'
    fi

    full_capacity="$(cat "$battery/charge_full" 2>/dev/null || cat "$battery/energy_full" 2>/dev/null || true)"
    design_capacity="$(cat "$battery/charge_full_design" 2>/dev/null || cat "$battery/energy_full_design" 2>/dev/null || true)"
    health_state="$(cat "$battery/health" 2>/dev/null || true)"
    if [[ "$full_capacity" =~ ^[0-9]+$ && "$design_capacity" =~ ^[1-9][0-9]*$ ]]; then
      awk -v full="$full_capacity" -v design="$design_capacity" -v state="$health_state" 'BEGIN {
        printf "%.1f%%", full / design * 100
        if (state != "") printf " (%s)", state
        printf "\n"
      }'
    elif [[ -n "$health_state" ]]; then
      printf '%s\n' "$health_state"
    else
      printf 'Unavailable\n'
    fi
    return 0
  done

  return 1
}

print_columns() {
  local left_title="$1"
  local left_name="$2"
  local right_title="$3"
  local right_name="$4"
  local left_color="$5"
  local right_color="$6"
  local -n left_lines="$left_name"
  local -n right_lines="$right_name"
  local terminal_width
  local left_width
  local right_width
  local row
  local row_count="${#left_lines[@]}"

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40
  left_width=$(( (terminal_width - 2) / 2 ))
  right_width=$(( terminal_width - left_width - 2 ))

  if (( ${#right_lines[@]} > row_count )); then
    row_count="${#right_lines[@]}"
  fi

  printf '%s%-*.*s%s  %s%-*.*s%s\n' \
    "$left_color" "$left_width" "$left_width" "$left_title" "$RESET" \
    "$right_color" "$right_width" "$right_width" "$right_title" "$RESET"
  for ((row = 0; row < row_count; row++)); do
    printf '%-*.*s  %-*.*s\n' \
      "$left_width" "$left_width" "${left_lines[row]:-}" \
      "$right_width" "$right_width" "${right_lines[row]:-}"
  done
}

print_mounts() {
  local source target fstype opts rest
  local size used avail usep
  local terminal_width row
  local -a rows=()
  local -A seen=()

  while read -r source target fstype opts rest; do
    # Decode common octal escapes used in /proc/mounts.
    target="${target//\\040/ }"
    source="${source//\\040/ }"

    case "$target" in
      /|/data) continue ;;
      /boot|/boot/*) continue ;;
    esac
    [[ -n "${seen[$target]:-}" ]] && continue

    case "$fstype" in
      proc|sysfs|tmpfs|devtmpfs|devpts|cgroup|cgroup2|mqueue|hugetlbfs|debugfs|tracefs|securityfs|pstore|bpf|configfs|fusectl|autofs|binfmt_misc|overlay|squashfs|ramfs|efivarfs|rpc_pipefs|nsfs|selinuxfs|fuse.gvfsd-fuse|"" )
        continue ;;
    esac

    local keep=false
    case "$source" in
      /dev/*) keep=true ;;
    esac
    case "$fstype" in
      nfs|nfs4|cifs|smb3|smbfs|sshfs|fuse.sshfs|9p|afs|ceph|glusterfs) keep=true ;;
    esac
    case "$target" in
      /mnt/*|/media/*|/run/media/*) keep=true ;;
    esac
    [[ "$keep" == true ]] || continue

    seen[$target]=1
    read -r size used avail usep < <(
      df -hT "$target" 2>/dev/null | awk 'NR==2 {print $3, $4, $5, $6}'
    )
    if [[ -n "$size" ]]; then
      rows+=("$target   $fstype on $source | $used / $size ($usep) | $avail free")
    else
      rows+=("$target   $fstype on $source")
    fi
  done < /proc/mounts

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '\n%s◈ Mounts%s\n' "$BLUE" "$RESET"
  if (( ${#rows[@]} == 0 )); then
    printf '%sNone%s\n' "$DIM" "$RESET"
  else
    for row in "${rows[@]}"; do
      printf '%.*s\n' "$terminal_width" "$row"
    done
  fi
}

print_info() {
  local disk_name
  local filesystem
  local total_storage
  local free_storage
  local used_storage
  local used_percent
  local total_memory
  local used_memory
  local available_memory
  local free_memory
  local cache_memory
  local mem_pct
  local cpu_effort
  local cpu_temp
  local cpu_model
  local os_name
  local battery_present
  local battery_color
  local storage_color
  local storage_percent
  local data_storage_percent
  local -a storage_info
  local -a memory_info
  local -a battery_info
  local -a system_lines
  local -a cpu_lines
  local -a memory_lines
  local -a battery_lines
  local -a storage_lines
  local -a data_storage_info
  local terminal_width

  readarray -t storage_info < <(storage_lines /)
  readarray -t memory_info < <(memory_lines)
  disk_name="${storage_info[0]:-unknown}"
  filesystem="${storage_info[1]:-unknown}"
  total_storage="${storage_info[2]:-unknown}"
  free_storage="${storage_info[3]:-unknown}"
  used_storage="${storage_info[4]:-unknown}"
  used_percent="${storage_info[5]:-unknown}"
  total_memory="${memory_info[0]:-unknown}"
  used_memory="${memory_info[1]:-unknown}"
  available_memory="${memory_info[2]:-unknown}"
  free_memory="${memory_info[3]:-unknown}"
  cache_memory="${memory_info[4]:-unknown}"
  mem_pct="$(memory_percent || true)"
  cpu_effort="$(cpu_effort_line || true)"
  cpu_temp="$(cpu_temp_line || true)"
  cpu_model="$(cpu_model_line || true)"
  os_name="$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-Linux}" || printf 'Linux')"

  battery_info=()
  readarray -t battery_info < <(battery_lines || true)
  if (( ${#battery_info[@]} > 0 )); then
    battery_present=true
  else
    battery_present=false
  fi

  system_lines=(
    "OS       $os_name"
    "Host     $(hostname)"
    "Kernel   $(uname -r)"
    "Uptime   $(friendly_uptime)"
  )
  cpu_lines=(
    "Model    ${cpu_model:-Unavailable}"
    "Load     $(awk '{print $1 ", " $2 ", " $3}' /proc/loadavg)"
    "Effort   ${cpu_effort:-Unavailable} | Temp ${cpu_temp:-Unavailable}"
  )
  memory_lines=(
    "Total    $total_memory | Used $used_memory (${mem_pct:-?}%) now"
    "Avail    $available_memory free | $cache_memory cached"
    "Free     $free_memory unused"
  )

  if [[ "$battery_present" == true ]]; then
    battery_color="$GREEN"
    if [[ "${battery_info[0]:-}" =~ ^[0-9]+$ ]]; then
      if (( 10#${battery_info[0]} < 20 )); then
        battery_color="$RED"
      elif (( 10#${battery_info[0]} < 50 )); then
        battery_color="$YELLOW"
      fi
    fi
    battery_lines=(
      "Charge   ${battery_info[0]:-unknown}% | ${battery_info[1]:-unknown}"
      "Health   ${battery_info[3]:-Unavailable} | Cycles ${battery_info[2]:-Unavailable}"
    )
  else
    battery_color="$DIM"
    battery_lines=("No battery available")
  fi

  storage_color="$GREEN"
  storage_percent="${used_percent%\%}"
  if [[ "$storage_percent" =~ ^[0-9]+$ ]]; then
    if (( 10#$storage_percent >= 90 )); then
      storage_color="$RED"
    elif (( 10#$storage_percent >= 75 )); then
      storage_color="$YELLOW"
    fi
  fi
  storage_lines=(
    "/      $filesystem on $disk_name | $used_storage / $total_storage ($used_percent) | $free_storage free"
  )

  if mountpoint -q /data; then
    data_storage_info=()
    readarray -t data_storage_info < <(storage_lines /data)
    data_storage_percent="${data_storage_info[5]:-0}"
    data_storage_percent="${data_storage_percent%\%}"
    if [[ "$data_storage_percent" =~ ^[0-9]+$ ]]; then
      if (( 10#$data_storage_percent >= 90 )); then
        storage_color="$RED"
      elif (( 10#$data_storage_percent >= 75 )) && [[ "$storage_color" != "$RED" ]]; then
        storage_color="$YELLOW"
      fi
    fi
    storage_lines+=(
      "/data  ${data_storage_info[1]:-unknown} on ${data_storage_info[0]:-unknown} | ${data_storage_info[4]:-unknown} / ${data_storage_info[2]:-unknown} (${data_storage_info[5]:-unknown}) | ${data_storage_info[3]:-unknown} free"
    )
  fi

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '%sForge Linux Info%s\n\n' "$BOLD" "$RESET"
  print_columns '● System' system_lines '◆ CPU' cpu_lines "$BLUE" "$CYAN"
  printf '\n'
  print_columns '▣ Memory' memory_lines '♥ Battery' battery_lines "$MAGENTA" "$battery_color"
  printf '\n%s■ Storage%s\n' "$storage_color" "$RESET"
  printf '%.*s\n' "$terminal_width" "${storage_lines[0]}"
  if (( ${#storage_lines[@]} > 1 )); then
    printf '%.*s\n' "$terminal_width" "${storage_lines[1]}"
  fi
  print_mounts
}

BOLD=""
DIM=""
BLUE=""
CYAN=""
MAGENTA=""
GREEN=""
YELLOW=""
RED=""
RESET=""
if [[ -t 1 && -z "${NO_COLOR+x}" ]]; then
  BOLD=$'\033[1m'
  DIM=$'\033[2m'
  BLUE=$'\033[34m'
  CYAN=$'\033[36m'
  MAGENTA=$'\033[35m'
  GREEN=$'\033[32m'
  YELLOW=$'\033[33m'
  RED=$'\033[31m'
  RESET=$'\033[0m'
fi

HISTORY_MIN_INTERVAL_SECONDS=60
HISTORY_CPU_DELTA_PERCENT=5
HISTORY_MEMORY_DELTA_PERCENT=1
HISTORY_TEMPERATURE_DELTA_C=1
HISTORY_STORAGE_DELTA_KIB=102400
HISTORY_LAST_EPOCH=0
HISTORY_LAST_SAMPLE=""
HISTORY_STATUS=""
HISTORY_TIMESTAMP=""
HISTORY_LOGICAL_CPU_COUNT=1
HISTORY_MONITOR_PID="$$"
AGENT_IDENTITIES=""

cycle_interval=""
if [[ "${1:-}" == "--cycle" ]]; then
  cycle_interval="${2:-5}"
  if [[ ! "$cycle_interval" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v value="$cycle_interval" 'BEGIN { exit !(value > 0) }'; then
    printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
    exit 2
  fi
  if (( $# > 2 )); then
    printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
    exit 2
  fi
elif (( $# > 0 )); then
  printf 'Usage: inf [--cycle [SECONDS]]\n' >&2
  exit 2
fi

if [[ -n "$cycle_interval" ]]; then
  HISTORY_LOGICAL_CPU_COUNT="$(logical_cpu_count)"
  AGENT_IDENTITIES="$(discover_station_agents)"
  history_file="$(create_history_log)"
  agent_history_file=""
  if [[ -n "$AGENT_IDENTITIES" ]]; then
    agent_history_file="$(create_agent_history_log "$history_file")"
  fi
  trap 'printf "\033[?25h"' EXIT
  printf '\033[?25l'
  while true; do
    sample="$(history_sample)"
    record_history_sample "$history_file" "$sample"
    if [[ "$HISTORY_STATUS" == "recorded" && -n "$agent_history_file" ]]; then
      record_agent_history_samples "$agent_history_file" "$HISTORY_TIMESTAMP" "$AGENT_IDENTITIES"
    fi
    snapshot="$(print_info)"
    printf '\033[H%s\n\nHistory  %s (%s)\n' "$snapshot" "$history_file" "$HISTORY_STATUS"
    [[ -z "$agent_history_file" ]] || printf 'Agents   %s\n' "$agent_history_file"
    printf '\033[J'
    sleep "$cycle_interval"
  done
else
  print_info
fi
