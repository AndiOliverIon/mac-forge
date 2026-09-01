#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
fi

format_size() {
  awk -v kib="$1" '
    BEGIN {
      bytes = kib * 1024
      split("B KB MB GB TB PB", units, " ")
      i = 1
      while (bytes >= 1000 && i < 6) {
        bytes /= 1000
        i++
      }
      printf "%.1f %s", bytes, units[i]
    }'
}

# Emits current memory usage in KiB: used cached free available percent
# "used" mirrors Activity Monitor (app + wired + compressed), i.e. what is
# actually occupied right now, unlike top's PhysMem "used" which also counts
# reclaimable cached/inactive pages.
memory_stats() {
  local total_bytes
  total_bytes="$(sysctl -n hw.memsize)"
  vm_stat | awk -v total="$total_bytes" '
    /page size of/ { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) ps = $i }
    /Pages free/ { free = $3 }
    /Pages speculative/ { spec = $3 }
    /Pages wired down/ { wired = $4 }
    /Pages purgeable/ { purge = $3 }
    /File-backed pages/ { fileb = $3 }
    /Anonymous pages/ { anon = $3 }
    /occupied by compressor/ { comp = $5 }
    END {
      gsub(/\./, "", free); gsub(/\./, "", spec); gsub(/\./, "", wired)
      gsub(/\./, "", purge); gsub(/\./, "", fileb); gsub(/\./, "", anon)
      gsub(/\./, "", comp)
      used = (anon - purge + wired + comp) * ps
      cached = fileb * ps
      freeb = free * ps
      avail = freeb + cached + (purge + spec) * ps
      pct = (total > 0) ? used / total * 100 : 0
      printf "%d %d %d %d %.0f\n", used / 1024, cached / 1024, freeb / 1024, avail / 1024, pct
    }'
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
  top -l 1 -n 0 2>/dev/null | awk -F': ' '/CPU usage/ {
    split($2, values, ", *")
    user=values[1]
    sys=values[2]
    gsub(/[^0-9.]/, "", user)
    gsub(/[^0-9.]/, "", sys)
    if (user != "" && sys != "") {
      printf "%s %s", user, sys
      exit
    }
  }'
}

history_sample() {
  local cpu_user cpu_system
  local memory_used memory_cached memory_free memory_available memory_used_percent
  local memory_total
  local root_total root_used root_used_percent

  read -r cpu_user cpu_system < <(cpu_history_values || true)
  memory_total="$(( $(sysctl -n hw.memsize) / 1024 ))"
  read -r memory_used memory_cached memory_free memory_available memory_used_percent < <(memory_stats)
  read -r root_total root_used root_used_percent < <(
    df -k / 2>/dev/null | awk 'NR==2 {percent=$5; sub(/%$/, "", percent); print $2, $3, percent}'
  )

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${cpu_user:-Unavailable}" \
    "${cpu_system:-Unavailable}" \
    "${memory_used:-Unavailable}" \
    "${memory_total:-Unavailable}" \
    "${memory_used_percent:-Unavailable}" \
    'Unavailable' \
    "${root_used:-Unavailable}" \
    "${root_total:-Unavailable}" \
    "${root_used_percent:-Unavailable}" \
    'Unavailable' \
    'Unavailable' \
    'Unavailable'
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

  printf '%s\t%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$sample" >> "$history_file"
  HISTORY_LAST_EPOCH="$now"
  HISTORY_LAST_SAMPLE="$sample"
  HISTORY_STATUS="recorded"
}

friendly_uptime() {
  local value
  local prefix=""
  local hours
  local minutes

  value="$(uptime | awk -F'up ' '{print $2}' | sed 's/, [0-9] user.*//')"
  if [[ "$value" =~ ^(.*),[[:space:]]*([0-9]+):([0-9][0-9])$ ]]; then
    prefix="${BASH_REMATCH[1]}, "
    hours="${BASH_REMATCH[2]}"
    minutes="${BASH_REMATCH[3]}"
  elif [[ "$value" =~ ^([0-9]+):([0-9][0-9])$ ]]; then
    hours="${BASH_REMATCH[1]}"
    minutes="${BASH_REMATCH[2]}"
  else
    printf '%s' "$value"
    return
  fi

  printf '%s%d hour' "$prefix" "$((10#$hours))"
  (( 10#$hours != 1 )) && printf 's'
  printf ' %d minute' "$((10#$minutes))"
  (( 10#$minutes != 1 )) && printf 's'
  return 0
}

date_epoch_utc() {
  TZ=UTC date -j -f '%Y-%m-%d %H:%M:%S' "$1 00:00:00" '+%s' 2>/dev/null
}

days_in_month() {
  local year="$1"
  local month="$2"

  case "$month" in
    1|3|5|7|8|10|12) printf '31' ;;
    4|6|9|11) printf '30' ;;
    2)
      if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then
        printf '29'
      else
        printf '28'
      fi
      ;;
  esac
}

format_calendar_interval() {
  local start_date="$1"
  local end_date="$2"
  local start_year start_month start_day
  local end_year end_month end_day
  local total_months candidate_year candidate_month candidate_day candidate_max_day
  local end_epoch candidate_epoch years months days
  local result=""

  IFS=- read -r start_year start_month start_day <<< "$start_date"
  IFS=- read -r end_year end_month end_day <<< "$end_date"
  start_year=$((10#$start_year))
  start_month=$((10#$start_month))
  start_day=$((10#$start_day))
  end_year=$((10#$end_year))
  end_month=$((10#$end_month))
  end_day=$((10#$end_day))
  total_months=$(( (end_year - start_year) * 12 + end_month - start_month ))
  end_epoch="$(date_epoch_utc "$end_date")"

  while true; do
    candidate_year=$(( start_year + (start_month - 1 + total_months) / 12 ))
    candidate_month=$(( (start_month - 1 + total_months) % 12 + 1 ))
    candidate_max_day="$(days_in_month "$candidate_year" "$candidate_month")"
    candidate_day="$start_day"
    (( candidate_day > candidate_max_day )) && candidate_day="$candidate_max_day"
    candidate_epoch="$(date_epoch_utc "$(printf '%04d-%02d-%02d' "$candidate_year" "$candidate_month" "$candidate_day")")"
    (( candidate_epoch <= end_epoch )) && break
    total_months=$((total_months - 1))
  done

  years=$(( total_months / 12 ))
  months=$(( total_months % 12 ))
  days=$(( (end_epoch - candidate_epoch) / 86400 ))

  if (( years > 0 )); then
    result="$years year"
    (( years != 1 )) && result+="s"
  fi
  if (( months > 0 )); then
    [[ -n "$result" ]] && result+=", "
    result+="$months month"
    (( months != 1 )) && result+="s"
  fi
  if (( days > 0 || (years == 0 && months == 0) )); then
    [[ -n "$result" ]] && result+=", "
    result+="$days day"
    (( days != 1 )) && result+="s"
  fi

  printf '%s' "$result"
}

mac_first_used_date() {
  local setup_epoch

  setup_epoch="$(stat -f '%B' /var/db/.AppleSetupDone 2>/dev/null || true)"
  if [[ "$setup_epoch" =~ ^[0-9]+$ ]] && (( setup_epoch > 0 )); then
    date -r "$setup_epoch" '+%Y-%m-%d'
  fi
}

print_columns() {
  local left_title="$1"
  local right_title="$2"
  local left_color="$3"
  local right_color="$4"
  local terminal_width
  local left_width
  local right_width

  shift 4
  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40
  left_width=$(( (terminal_width - 2) / 2 ))
  right_width=$(( terminal_width - left_width - 2 ))

  printf '%s%-*.*s%s  %s%-*.*s%s\n' \
    "$left_color" "$left_width" "$left_width" "$left_title" "$RESET" \
    "$right_color" "$right_width" "$right_width" "$right_title" "$RESET"
  while (( $# >= 2 )); do
    printf '%-*.*s  %-*.*s\n' \
      "$left_width" "$left_width" "$1" \
      "$right_width" "$right_width" "$2"
    shift 2
  done
}

print_mounts() {
  local line dev rest mp opts fstype
  local rows=()
  local terminal_width

  while IFS= read -r line; do
    dev="${line%% on *}"
    rest="${line#* on }"
    mp="${rest%% (*}"
    opts="${rest#*(}"
    opts="${opts%)}"
    fstype="${opts%%,*}"

    case "$mp" in
      /Volumes/*) ;;
      *)
        case "$fstype" in
          smbfs|nfs|afpfs|webdav|cifs|ftp) ;;
          *) continue ;;
        esac
        ;;
    esac

    local total_kib used_kib free_kib percent
    read -r total_kib used_kib free_kib percent < <(
      df -k "$mp" 2>/dev/null | awk 'NR==2 {print $2, $3, $4, $5}'
    )
    if [[ -n "$total_kib" ]]; then
      rows+=("$mp   ${fstype} on ${dev} | $(format_size "$used_kib") / $(format_size "$total_kib") (${percent}) | $(format_size "$free_kib") free")
    else
      rows+=("$mp   ${fstype} on ${dev}")
    fi
  done < <(mount)

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '\n%s◈ Mounts%s\n' "$BLUE" "$RESET"
  if (( ${#rows[@]} == 0 )); then
    printf '%sNone%s\n' "$DIM" "$RESET"
  else
    local row
    for row in "${rows[@]}"; do
      printf '%.*s\n' "$terminal_width" "$row"
    done
  fi
}

print_info() {
  local top_output
  local cpu_effort
  local phys_mem
  local used_memory
  local available_memory
  local total_memory_kib
  local disk_name
  local disk_total_kib
  local disk_used_kib
  local disk_free_kib
  local disk_percent
  local filesystem
  local os_name
  local kernel
  local host_name
  local uptime_value
  local cpu_model
  local cpu_load
  local battery_output
  local charge
  local charge_percent
  local status
  local power_info
  local cycles
  local max_capacity
  local condition
  local health
  local battery_color
  local storage_color
  local storage_percent
  local terminal_width
  local system_os
  local system_host
  local system_kernel
  local system_uptime
  local system_since
  local system_days
  local system_age
  local cpu_model_row
  local cpu_load_row
  local cpu_effort_row
  local memory_total
  local memory_free
  local memory_boot
  local mem_used_kib
  local mem_cached_kib
  local mem_free_kib
  local mem_avail_kib
  local mem_pct
  local battery_charge
  local battery_health
  local storage_row
  local first_used_date
  local first_used_epoch
  local today_date
  local today_epoch
  local elapsed_days
  local elapsed_interval

  top_output="$(top -l 1 -n 0)"
  cpu_effort="$(printf '%s\n' "$top_output" | awk -F': ' '/CPU usage/ {
    split($2, values, ", *")
    printf "%s, %s", values[1], values[2]
    exit
  }')"
  phys_mem="$(printf '%s\n' "$top_output" | awk '/PhysMem/ {print; exit}')"
  used_memory="$(printf '%s\n' "$phys_mem" | sed -E 's/.*PhysMem: ([^ ]+) used.*/\1/')"
  available_memory="$(printf '%s\n' "$phys_mem" | sed -E 's/.*, ([^ ]+) unused.*/\1/')"
  total_memory_kib="$(( $(sysctl -n hw.memsize) / 1024 ))"
  read -r mem_used_kib mem_cached_kib mem_free_kib mem_avail_kib mem_pct < <(memory_stats)

  read -r disk_name disk_total_kib disk_used_kib disk_free_kib disk_percent < <(
    df -k / | awk 'NR==2 {print $1, $2, $3, $4, $5}'
  )
  filesystem="$(diskutil info / 2>/dev/null \
    | awk -F: '/File System Personality/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

  os_name="$(sw_vers -productName) $(sw_vers -productVersion)"
  kernel="$(uname -r)"
  host_name="$(hostname)"
  uptime_value="$(friendly_uptime)"
  cpu_model="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model)"
  cpu_load="$(sysctl -n vm.loadavg | awk '{print $2 ", " $3 ", " $4}')"

  first_used_date="$(mac_first_used_date)"
  today_date="$(date '+%Y-%m-%d')"
  first_used_epoch="$(date_epoch_utc "$first_used_date" || true)"
  today_epoch="$(date_epoch_utc "$today_date")"
  if [[ "$first_used_epoch" =~ ^[0-9]+$ ]] && (( first_used_epoch <= today_epoch )); then
    elapsed_days=$(( (today_epoch - first_used_epoch) / 86400 ))
    elapsed_interval="$(format_calendar_interval "$first_used_date" "$today_date")"
    system_since="Since    $first_used_date"
    system_days="Days     $elapsed_days total"
    system_age="Age      $elapsed_interval"
  else
    system_since="Since    Unavailable"
    system_days="Days     Unavailable"
    system_age="Age      Unavailable"
  fi

  battery_output="$(pmset -g batt 2>/dev/null || true)"
  charge="$(printf '%s\n' "$battery_output" | grep -Eo '[0-9]+%' | head -n1 || true)"
  if [[ -n "$charge" ]]; then
    status="$(printf '%s\n' "$battery_output" \
      | awk -F';' '/[0-9]+%/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    power_info="$(system_profiler SPPowerDataType 2>/dev/null || true)"
    cycles="$(printf '%s\n' "$power_info" \
      | awk -F: '/Cycle Count/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    max_capacity="$(printf '%s\n' "$power_info" \
      | awk -F: '/Maximum Capacity/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"
    condition="$(printf '%s\n' "$power_info" \
      | awk -F: '/Condition/ {value=$2; sub(/^[[:space:]]+/, "", value); print value; exit}')"

    health="${max_capacity:-Unavailable}"
    if [[ -n "$condition" && "$health" != 'Unavailable' ]]; then
      health="$health ($condition)"
    elif [[ -n "$condition" ]]; then
      health="$condition"
    fi

    battery_color="$GREEN"
    charge_percent="${charge%\%}"
    if [[ "$charge_percent" =~ ^[0-9]+$ ]]; then
      if (( 10#$charge_percent < 20 )); then
        battery_color="$RED"
      elif (( 10#$charge_percent < 50 )); then
        battery_color="$YELLOW"
      fi
    fi
    battery_charge="Charge   $charge | ${status:-unknown}"
    battery_health="Health   $health | Cycles ${cycles:-Unavailable}"
  else
    battery_color="$DIM"
    battery_charge="No battery available"
    battery_health=""
  fi

  storage_color="$GREEN"
  storage_percent="${disk_percent%\%}"
  if [[ "$storage_percent" =~ ^[0-9]+$ ]]; then
    if (( 10#$storage_percent >= 90 )); then
      storage_color="$RED"
    elif (( 10#$storage_percent >= 75 )); then
      storage_color="$YELLOW"
    fi
  fi

  system_os="OS       $os_name"
  system_host="Host     $host_name"
  system_kernel="Kernel   $kernel"
  system_uptime="Uptime   $uptime_value"
  cpu_model_row="Model    ${cpu_model:-Unavailable}"
  cpu_load_row="Load     $cpu_load"
  cpu_effort_row="Effort   ${cpu_effort:-Unavailable} | Temp Unavailable"
  memory_total="Total    $(format_size "$total_memory_kib") | Used $(format_size "$mem_used_kib") (${mem_pct}%) now"
  memory_free="Avail    $(format_size "$mem_avail_kib") free | $(format_size "$mem_cached_kib") cached"
  memory_boot="Boot     ${used_memory:-?} used, ${available_memory:-?} free (cached)"
  storage_row="/      ${filesystem:-unknown} on $disk_name | $(format_size "$disk_used_kib") / $(format_size "$disk_total_kib") ($disk_percent) | $(format_size "$disk_free_kib") free"

  terminal_width="$(tput cols 2>/dev/null || printf '80')"
  (( terminal_width < 40 )) && terminal_width=40

  printf '%sForge macOS Info%s\n\n' "$BOLD" "$RESET"
  print_columns '● System' '◆ CPU' "$BLUE" "$CYAN" \
    "$system_os" "$cpu_model_row" \
    "$system_host" "$cpu_load_row" \
    "$system_kernel" "$cpu_effort_row" \
    "$system_uptime" "" \
    "$system_since" "" \
    "$system_days" "" \
    "$system_age" ""
  printf '\n'
  print_columns '▣ Memory' '♥ Battery' "$MAGENTA" "$battery_color" \
    "$memory_total" "$battery_charge" \
    "$memory_free" "$battery_health" \
    "$memory_boot" ""
  printf '\n%s■ Storage%s\n' "$storage_color" "$RESET"
  printf '%.*s\n' "$terminal_width" "$storage_row"
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
  history_file="$(create_history_log)"
  trap 'printf "\033[?25h"' EXIT
  printf '\033[?25l'
  while true; do
    sample="$(history_sample)"
    record_history_sample "$history_file" "$sample"
    snapshot="$(print_info)"
    printf '\033[H%s\n\nHistory  %s (%s)\n\033[J' "$snapshot" "$history_file" "$HISTORY_STATUS"
    sleep "$cycle_interval"
  done
else
  print_info
fi
