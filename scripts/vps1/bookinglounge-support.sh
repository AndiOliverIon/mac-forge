#!/usr/bin/env bash
# bookinglounge-support.sh — inspect and operate BookingLounge owner-support threads.
#
# Interactive:
#   bookinglounge-support.sh
#
# Scriptable:
#   bookinglounge-support.sh list --env production [--status pending|engaged|closed|all]
#   bookinglounge-support.sh owners --env development
#   bookinglounge-support.sh threads --env production --owner <owner-guid|email|shop-identifier>
#   bookinglounge-support.sh show --env production <thread-guid>
#   bookinglounge-support.sh reply --env development <thread-guid> [--file path|--stdin]
#   bookinglounge-support.sh state --env development <thread-guid> <pending|engaged|closed>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vps1.sh"

BL_ENV=""
BL_ENV_LABEL=""
BL_DATABASE=""
BL_CONNECTION_NAME=""
BL_REMOTE_ENV_FILE=""
BL_API_PORT=""
BL_COMMAND=""
BL_STATUS_FILTER="pending"
BL_OWNER_SELECTOR=""
BL_REPLY_FILE=""
BL_REPLY_STDIN=0
BL_PREVIEW_FILE=""
declare -a BL_POSITIONAL=()

usage() {
  sed -n '2,/^set -euo pipefail$/p' "${BASH_SOURCE[0]}" |
    sed '$d; s/^# \{0,1\}//'
}

bl_die() {
  echo "✖ $*" >&2
  exit 1
}

bl_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

bl_cleanup_preview() {
  if [[ -n "$BL_PREVIEW_FILE" && -f "$BL_PREVIEW_FILE" ]]; then
    rm -f -- "$BL_PREVIEW_FILE"
  fi
  BL_PREVIEW_FILE=""
}

bl_create_preview() {
  bl_cleanup_preview
  BL_PREVIEW_FILE="$(mktemp "${TMPDIR:-/tmp}/bookinglounge-support.XXXXXX")" ||
    bl_die "Could not create a temporary conversation preview."
  chmod 600 "$BL_PREVIEW_FILE"
}

trap bl_cleanup_preview EXIT

bl_require_uuid() {
  local value="$1"
  [[ "$value" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] ||
    bl_die "Expected a UUID, got: $value"
}

bl_require_status() {
  case "$1" in
    pending | engaged | closed | all) ;;
    *) bl_die "Invalid status '$1' (expected pending, engaged, closed, or all)." ;;
  esac
}

bl_choose_environment() {
  local selection
  selection="$({
    printf 'dev\tDevelopment\tbookinglounge-dev\n'
    printf 'prod\tProduction ⚠ live data\tbookinglounge\n'
    printf '__QUIT__\tQuit\t\n'
  } | fzf \
    --height=35% \
    --layout=reverse \
    --border \
    --no-sort \
    --delimiter=$'\t' \
    --with-nth=2,3 \
    --prompt='BookingLounge environment > ' \
    --header='Development is private · production contains real owner data')" || return 1
  BL_ENV="${selection%%$'\t'*}"
  [[ "$BL_ENV" != "__QUIT__" ]] || return 1
}

bl_configure_environment() {
  case "$BL_ENV" in
    dev | development)
      BL_ENV="dev"
      BL_ENV_LABEL="Development"
      BL_DATABASE="bookinglounge-dev"
      BL_CONNECTION_NAME="BookingLounge Development (VPS1)"
      BL_REMOTE_ENV_FILE="/srv/tnisoft/bookinglounge-api/shared/bookinglounge-api-dev.env"
      BL_API_PORT="5081"
      ;;
    prod | production)
      BL_ENV="prod"
      BL_ENV_LABEL="Production"
      BL_DATABASE="bookinglounge"
      BL_CONNECTION_NAME="BookingLounge Production (VPS1)"
      BL_REMOTE_ENV_FILE="/srv/tnisoft/bookinglounge-api/shared/bookinglounge-api-prod.env"
      BL_API_PORT="5080"
      ;;
    *) bl_die "Invalid environment '$BL_ENV' (expected development/dev or production/prod)." ;;
  esac

  VPS1_CONNECTION_NAME="$BL_CONNECTION_NAME"
  unset VPS1_SQL_HOST VPS1_SQL_PORT VPS1_SQL_USER VPS1_SQL_PASSWORD VPS1_SQL_SERVER || true
  vps1_load_connection
  vps1_wait_for_sql_ready 10
  bl_verify_schema
}

bl_sql_json() {
  local query="$1"
  local output
  output="$(
    vps1_sqlcmd \
      -b \
      -d "$BL_DATABASE" \
      -h -1 \
      -w 65535 \
      -y 0 \
      -Q "$query" |
      tr -d '\r'
  )" || bl_die "SQL query failed for $BL_ENV_LABEL ($BL_DATABASE)."
  output="$(bl_trim "$output")"
  [[ -n "$output" ]] || output='[]'
  jq -e . >/dev/null 2>&1 <<<"$output" ||
    bl_die "The database returned an unexpected non-JSON response."
  printf '%s' "$output"
}

bl_verify_schema() {
  local result
  result="$(
    vps1_sqlcmd \
      -b \
      -d "$BL_DATABASE" \
      -h -1 \
      -W \
      -Q "SET NOCOUNT ON;
          SELECT CASE
            WHEN OBJECT_ID(N'dbo.SupportThread', N'U') IS NOT NULL
             AND OBJECT_ID(N'dbo.SupportMessage', N'U') IS NOT NULL
            THEN N'ready' ELSE N'missing' END;" |
      tr -d '\r' |
      sed '/^$/d' |
      head -n 1
  )"
  [[ "$result" == "ready" ]] ||
    bl_die "Owner-support schema is missing from $BL_DATABASE."
}

bl_active_threads_json() {
  local status="$1"
  local status_clause=""
  case "$status" in
    pending | engaged) status_clause="st.ClosedAt IS NULL AND st.Status = N'$status'" ;;
    closed) status_clause="st.ClosedAt IS NOT NULL AND st.Status = N'closed'" ;;
    all) status_clause="1 = 1" ;;
  esac
  bl_sql_json "
SET NOCOUNT ON;
SELECT
  st.Id AS threadID,
  st.OwnerProfileId AS ownerProfileID,
  o.fullname AS ownerName,
  o.email AS ownerEmail,
  s.name AS shopName,
  s.identifier AS shopIdentifier,
  st.Status AS status,
  CONVERT(varchar(19), st.CreatedAt, 120) AS createdAtUtc,
  CONVERT(varchar(19), st.UpdatedAt, 120) AS updatedAtUtc,
  COALESCE((
    SELECT COUNT_BIG(1)
    FROM dbo.SupportMessage AS owner_message
    WHERE owner_message.ThreadId = st.Id
      AND owner_message.Sender = N'owner'
      AND owner_message.SequenceNumber > COALESCE((
        SELECT MAX(support_message.SequenceNumber)
        FROM dbo.SupportMessage AS support_message
        WHERE support_message.ThreadId = st.Id
          AND support_message.Sender = N'support'
      ), 0)
  ), 0) AS unansweredOwnerMessages,
  (SELECT TOP (1) last_message.Sender
   FROM dbo.SupportMessage AS last_message
   WHERE last_message.ThreadId = st.Id
   ORDER BY last_message.SequenceNumber DESC) AS lastSender,
  (SELECT TOP (1) last_message.AppVersion
   FROM dbo.SupportMessage AS last_message
   WHERE last_message.ThreadId = st.Id
     AND last_message.Sender = N'owner'
   ORDER BY last_message.SequenceNumber DESC) AS appVersion,
  (SELECT TOP (1) last_message.AppBuild
   FROM dbo.SupportMessage AS last_message
   WHERE last_message.ThreadId = st.Id
     AND last_message.Sender = N'owner'
   ORDER BY last_message.SequenceNumber DESC) AS appBuild
FROM dbo.SupportThread AS st
INNER JOIN dbo.ownerprofiles AS o ON o.id = st.OwnerProfileId
INNER JOIN dbo.shops AS s ON s.ownerprofileid = st.OwnerProfileId
WHERE $status_clause
ORDER BY st.UpdatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;"
}

bl_owners_json() {
  bl_sql_json "
SET NOCOUNT ON;
SELECT
  o.id AS ownerProfileID,
  o.fullname AS ownerName,
  o.email AS ownerEmail,
  s.name AS shopName,
  s.identifier AS shopIdentifier,
  st.Id AS activeThreadID,
  st.Status AS activeStatus,
  CONVERT(varchar(19), st.UpdatedAt, 120) AS updatedAtUtc,
  COALESCE((
    SELECT COUNT_BIG(1)
    FROM dbo.SupportMessage AS owner_message
    WHERE owner_message.ThreadId = st.Id
      AND owner_message.Sender = N'owner'
      AND owner_message.SequenceNumber > COALESCE((
        SELECT MAX(support_message.SequenceNumber)
        FROM dbo.SupportMessage AS support_message
        WHERE support_message.ThreadId = st.Id
          AND support_message.Sender = N'support'
      ), 0)
  ), 0) AS unansweredOwnerMessages,
  (SELECT TOP (1) last_message.AppVersion
   FROM dbo.SupportMessage AS last_message
   WHERE last_message.ThreadId = st.Id
     AND last_message.Sender = N'owner'
   ORDER BY last_message.SequenceNumber DESC) AS appVersion,
  (SELECT TOP (1) last_message.AppBuild
   FROM dbo.SupportMessage AS last_message
   WHERE last_message.ThreadId = st.Id
     AND last_message.Sender = N'owner'
   ORDER BY last_message.SequenceNumber DESC) AS appBuild
FROM dbo.SupportThread AS st
INNER JOIN dbo.ownerprofiles AS o ON o.id = st.OwnerProfileId
INNER JOIN dbo.shops AS s ON s.ownerprofileid = o.id
WHERE st.ClosedAt IS NULL
ORDER BY
  CASE WHEN st.Status = N'pending' THEN 0 ELSE 1 END,
  st.UpdatedAt DESC,
  o.fullname
FOR JSON PATH, INCLUDE_NULL_VALUES;"
}

bl_threads_json() {
  local owner_id="$1"
  bl_require_uuid "$owner_id"
  bl_sql_json "
SET NOCOUNT ON;
SELECT
  st.Id AS threadID,
  st.OwnerProfileId AS ownerProfileID,
  st.Status AS status,
  CASE WHEN st.ClosedAt IS NULL THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS isActive,
  CONVERT(varchar(19), st.CreatedAt, 120) AS createdAtUtc,
  CONVERT(varchar(19), st.UpdatedAt, 120) AS updatedAtUtc,
  CONVERT(varchar(19), st.ClosedAt, 120) AS closedAtUtc,
  (SELECT COUNT_BIG(1)
   FROM dbo.SupportMessage AS message
   WHERE message.ThreadId = st.Id) AS messageCount
FROM dbo.SupportThread AS st
WHERE st.OwnerProfileId = CAST('$owner_id' AS uniqueidentifier)
ORDER BY
  CASE WHEN st.ClosedAt IS NULL THEN 0 ELSE 1 END,
  st.UpdatedAt DESC
FOR JSON PATH, INCLUDE_NULL_VALUES;"
}

bl_thread_json() {
  local thread_id="$1"
  bl_require_uuid "$thread_id"
  bl_sql_json "
SET NOCOUNT ON;
SELECT
  st.Id AS threadID,
  st.OwnerProfileId AS ownerProfileID,
  o.fullname AS ownerName,
  o.email AS ownerEmail,
  s.name AS shopName,
  s.identifier AS shopIdentifier,
  st.Status AS status,
  CASE WHEN st.ClosedAt IS NULL THEN CAST(1 AS bit) ELSE CAST(0 AS bit) END AS isActive,
  CONVERT(varchar(19), st.CreatedAt, 120) AS createdAtUtc,
  CONVERT(varchar(19), st.UpdatedAt, 120) AS updatedAtUtc,
  CONVERT(varchar(19), st.ClosedAt, 120) AS closedAtUtc,
  JSON_QUERY((
    SELECT
      sm.Id AS messageID,
      sm.SequenceNumber AS sequenceNumber,
      sm.Sender AS sender,
      sm.Body AS body,
      sm.ContextScreen AS contextScreen,
      sm.AppVersion AS appVersion,
      sm.AppBuild AS appBuild,
      CONVERT(varchar(19), sm.CreatedAt, 120) AS createdAtUtc,
      CONVERT(varchar(19), sm.ReadAt, 120) AS readAtUtc
    FROM dbo.SupportMessage AS sm
    WHERE sm.ThreadId = st.Id
    ORDER BY sm.SequenceNumber
    FOR JSON PATH, INCLUDE_NULL_VALUES
  )) AS messages
FROM dbo.SupportThread AS st
INNER JOIN dbo.ownerprofiles AS o ON o.id = st.OwnerProfileId
INNER JOIN dbo.shops AS s ON s.ownerprofileid = st.OwnerProfileId
WHERE st.Id = CAST('$thread_id' AS uniqueidentifier)
FOR JSON PATH, INCLUDE_NULL_VALUES, WITHOUT_ARRAY_WRAPPER;"
}

bl_resolve_owner_id() {
  local selector="$1"
  local owners_json matches count
  owners_json="$(bl_sql_json "
SET NOCOUNT ON;
SELECT
  o.id AS ownerProfileID,
  o.email AS ownerEmail,
  s.identifier AS shopIdentifier
FROM dbo.ownerprofiles AS o
INNER JOIN dbo.shops AS s ON s.ownerprofileid = o.id
WHERE EXISTS (
  SELECT 1
  FROM dbo.SupportThread AS st
  WHERE st.OwnerProfileId = o.id
)
FOR JSON PATH, INCLUDE_NULL_VALUES;")"
  matches="$(
    jq -c --arg selector "$selector" '
      [.[] | select(
        ((.ownerProfileID // "") | ascii_downcase) == ($selector | ascii_downcase)
        or ((.ownerEmail // "") | ascii_downcase) == ($selector | ascii_downcase)
        or ((.shopIdentifier // "") | ascii_downcase) == ($selector | ascii_downcase)
      )]
    ' <<<"$owners_json"
  )"
  count="$(jq 'length' <<<"$matches")"
  ((count == 1)) || bl_die "Owner selector '$selector' matched $count owners. Use an exact owner UUID, email, or shop identifier."
  jq -r '.[0].ownerProfileID' <<<"$matches"
}

bl_print_active_threads() {
  local status="$1"
  local json
  json="$(bl_active_threads_json "$status")"
  if [[ "$(jq 'length' <<<"$json")" == "0" ]]; then
    echo "No support threads matched status '$status' in $BL_ENV_LABEL."
    return 0
  fi
  {
    printf 'THREAD\tSTATUS\tWAITING\tOWNER\tSHOP\tAPP\tUPDATED UTC\n'
    jq -r '.[] | [
      .threadID,
      .status,
      (.unansweredOwnerMessages | tostring),
      .ownerName,
      (.shopName + " (" + .shopIdentifier + ")"),
      (if .appVersion then .appVersion + (if .appBuild then " (" + .appBuild + ")" else "" end) else "—" end),
      .updatedAtUtc
    ] | @tsv' <<<"$json"
  } | column -t -s $'\t'
}

bl_print_owners() {
  local json
  json="$(bl_owners_json)"
  if [[ "$(jq 'length' <<<"$json")" == "0" ]]; then
    echo "No owners have an open support thread in $BL_ENV_LABEL."
    return 0
  fi
  {
    printf 'OWNER ID\tOWNER\tEMAIL\tSHOP\tSTATE\tWAITING\tAPP\tUPDATED UTC\n'
    jq -r '.[] | [
      .ownerProfileID,
      .ownerName,
      .ownerEmail,
      (.shopName + " (" + .shopIdentifier + ")"),
      .activeStatus,
      (.unansweredOwnerMessages | tostring),
      (if .appVersion then .appVersion + (if .appBuild then " (" + .appBuild + ")" else "" end) else "—" end),
      .updatedAtUtc
    ] | @tsv' <<<"$json"
  } | column -t -s $'\t'
}

bl_print_threads() {
  local owner_id="$1"
  local json
  json="$(bl_threads_json "$owner_id")"
  if [[ "$(jq 'length' <<<"$json")" == "0" ]]; then
    echo "No support threads found for owner $owner_id in $BL_ENV_LABEL."
    return 0
  fi
  {
    printf 'THREAD\tSTATUS\tACTIVE\tMESSAGES\tCREATED UTC\tUPDATED UTC\tCLOSED UTC\n'
    jq -r '.[] | [
      .threadID,
      .status,
      (if .isActive then "yes" else "no" end),
      (.messageCount | tostring),
      .createdAtUtc,
      .updatedAtUtc,
      (.closedAtUtc // "—")
    ] | @tsv' <<<"$json"
  } | column -t -s $'\t'
}

bl_card_width() {
  local width="${COLUMNS:-80}"
  [[ "$width" =~ ^[0-9]+$ ]] || width=80
  ((width > 96)) && width=96
  ((width < 56)) && width=56
  printf '%s' "$width"
}

bl_card_rule() {
  local edge="$1"
  local width rule
  width="$(bl_card_width)"
  printf -v rule '%*s' "$((width - 1))" ''
  rule="${rule// /─}"
  printf '%s%s\n' "$edge" "$rule"
}

bl_print_wrapped_body() {
  local body="$1"
  local width
  width="$(($(bl_card_width) - 5))"
  printf '%s' "$body" | python3 -c '
import sys
import textwrap

width = int(sys.argv[1])
text = sys.stdin.read()
lines = text.splitlines() or [""]
for source in lines:
    if not source.strip():
        print("│")
        continue
    wrapped = textwrap.wrap(
        source,
        width=width,
        break_long_words=True,
        break_on_hyphens=False,
        replace_whitespace=False,
    ) or [""]
    for line in wrapped:
        print("│  " + line)
' "$width"
}

bl_print_message_card() {
  local message="$1"
  local ordinal="$2"
  local total="$3"
  local sender body created context app_version app_build read_at
  local label color reset muted diagnostic=""
  sender="$(jq -r '.sender' <<<"$message")"
  body="$(jq -r '.body' <<<"$message")"
  created="$(jq -r '.createdAtUtc' <<<"$message")"
  context="$(jq -r '.contextScreen // empty' <<<"$message")"
  app_version="$(jq -r '.appVersion // empty' <<<"$message")"
  app_build="$(jq -r '.appBuild // empty' <<<"$message")"
  read_at="$(jq -r '.readAtUtc // empty' <<<"$message")"

  color=""
  reset=""
  muted=""
  if { [[ -t 1 ]] || [[ "${BL_FORCE_COLOR:-0}" == "1" ]]; } && [[ -z "${NO_COLOR:-}" ]]; then
    reset=$'\033[0m'
    muted=$'\033[2m'
    if [[ "$sender" == "owner" ]]; then
      color=$'\033[1;33m'
    else
      color=$'\033[1;36m'
    fi
  fi

  if [[ "$sender" == "owner" ]]; then
    label="OWNER"
    [[ -n "$context" ]] && diagnostic="Screen: $context"
    if [[ -n "$app_version" ]]; then
      [[ -n "$diagnostic" ]] && diagnostic+=" · "
      diagnostic+="App: $app_version"
      [[ -n "$app_build" ]] && diagnostic+=" ($app_build)"
    fi
  else
    label="YOU / SUPPORT"
    if [[ -n "$read_at" ]]; then
      diagnostic="Read by owner: $read_at UTC"
    else
      diagnostic="Not read by owner yet"
    fi
  fi

  echo
  printf '%s┌─ %s%s · MESSAGE %s OF %s\n' "$color" "$label" "$reset" "$ordinal" "$total"
  printf '│  %s%s UTC%s\n' "$muted" "$created" "$reset"
  [[ -n "$diagnostic" ]] && printf '│  %s%s%s\n' "$muted" "$diagnostic" "$reset"
  bl_card_rule '├'
  bl_print_wrapped_body "$body"
  bl_card_rule '└'
}

bl_display_thread_json() {
  local json="$1"
  [[ "$(jq -r 'type' <<<"$json")" == "object" ]] ||
    bl_die "Support thread was not found in $BL_ENV_LABEL."

  local status active
  status="$(jq -r '.status' <<<"$json")"
  active="$(jq -r '.isActive' <<<"$json")"

  echo
  echo "════════════════════════════════════════════════════════════════"
  printf ' BookingLounge Support · %s · %s\n' "$BL_ENV_LABEL" "$BL_DATABASE"
  echo "════════════════════════════════════════════════════════════════"
  jq -r '
    "Owner    : " + .ownerName + " <" + .ownerEmail + ">\n" +
    "Shop     : " + .shopName + " (" + .shopIdentifier + ")\n" +
    "Thread   : " + .threadID + "\n" +
    "State    : " + .status + (if .isActive then " · active" else " · closed history" end) + "\n" +
    "Updated  : " + .updatedAtUtc + " UTC"
  ' <<<"$json"
  echo "────────────────────────────────────────────────────────────────"

  local message_count message_number=0
  message_count="$(jq '.messages | length' <<<"$json")"
  if [[ "$message_count" == "0" ]]; then
    echo "(no messages)"
  else
    while IFS= read -r message; do
      ((message_number += 1))
      bl_print_message_card "$message" "$message_number" "$message_count"
    done < <(jq -c '.messages[]' <<<"$json")
  fi
  echo
  echo "────────────────────────────────────────────────────────────────"
  printf 'State: %s · %s\n' "$status" "$([[ "$active" == "true" ]] && echo active || echo history)"
}

bl_fetch_and_display_thread() {
  local thread_id="$1"
  local json
  json="$(bl_thread_json "$thread_id")"
  bl_display_thread_json "$json"
}

bl_confirm_write() {
  local action="$1"
  local owner="$2"
  local shop="$3"
  local thread_id="$4"
  echo
  echo "About to $action:"
  echo "  Environment : $BL_ENV_LABEL ($BL_DATABASE)"
  echo "  Owner       : $owner"
  echo "  Shop        : $shop"
  echo "  Thread      : $thread_id"
  echo
  if [[ "$BL_ENV" == "prod" ]]; then
    echo "⚠ This changes the production BookingLounge database."
    read -r -p "Type 'production' to continue: " answer </dev/tty
    [[ "$answer" == "production" ]] || return 1
  else
    read -r -p "Proceed in development? [y/N] " answer </dev/tty
    [[ "$answer" == "y" || "$answer" == "Y" ]] || return 1
  fi
}

bl_normalize_reply() {
  python3 -c '
import sys
value = sys.stdin.read().strip()
length = len(value.encode("utf-16-le")) // 2
if not value:
    raise SystemExit(2)
if length > 4000:
    raise SystemExit(3)
sys.stdout.write(value)
'
}

bl_read_reply() {
  local message=""
  if [[ -n "$BL_REPLY_FILE" ]]; then
    [[ -f "$BL_REPLY_FILE" ]] || bl_die "Reply file not found: $BL_REPLY_FILE"
    message="$(<"$BL_REPLY_FILE")"
  elif ((BL_REPLY_STDIN == 1)); then
    message="$(cat)"
  else
    echo "Enter the support reply on one line. Use --file or --stdin for multiline text."
    read -r -p "> " message </dev/tty
  fi

  local normalized
  if normalized="$(printf '%s' "$message" | bl_normalize_reply)"; then
    :
  else
    local validation_status=$?
    case "$validation_status" in
      2) bl_die "Reply cannot be blank." ;;
      3) bl_die "Reply exceeds 4000 UTF-16 code units." ;;
      *) bl_die "Reply could not be validated." ;;
    esac
  fi
  printf '%s' "$normalized"
}

bl_send_reply() {
  local thread_id="$1"
  local message="$2"
  bl_require_uuid "$thread_id"

  local thread_json owner shop active latest_sequence payload remote_command response http_status response_body
  thread_json="$(bl_thread_json "$thread_id")"
  [[ "$(jq -r 'type' <<<"$thread_json")" == "object" ]] ||
    bl_die "Support thread was not found in $BL_ENV_LABEL."
  active="$(jq -r '.isActive' <<<"$thread_json")"
  [[ "$active" == "true" ]] || bl_die "Closed support threads are read-only."
  owner="$(jq -r '.ownerName' <<<"$thread_json")"
  shop="$(jq -r '.shopName + " (" + .shopIdentifier + ")"' <<<"$thread_json")"
  latest_sequence="$(jq -r '[.messages[].sequenceNumber] | max // 0' <<<"$thread_json")"

  echo
  echo "Reply preview:"
  echo "────────────────────────────────────────────────────────────────"
  printf '%s\n' "$message"
  echo "────────────────────────────────────────────────────────────────"
  bl_confirm_write "send this support reply" "$owner" "$shop" "$thread_id" ||
    bl_die "Cancelled (no reply sent)."

  payload="$(jq -nc \
    --arg body "$message" \
    --argjson expectedLatestSequenceNumber "$latest_sequence" \
    '{body: $body, expectedLatestSequenceNumber: $expectedLatestSequenceNumber}')"
  remote_command="
set -euo pipefail
. '$BL_REMOTE_ENV_FILE'
token=\"\${BookingLounge__SupportAutomation__Token:-}\"
if [[ -z \"\$token\" ]]; then
  echo 'Support automation token is missing.' >&2
  exit 3
fi
curl -sS --connect-timeout 10 --max-time 30 \\
  -X POST \\
  -H \"Authorization: Bearer \$token\" \\
  -H 'Content-Type: application/json' \\
  --data-binary @- \\
  -w '\\n%{http_code}' \\
  'http://127.0.0.1:$BL_API_PORT/v1/support/threads/$thread_id/messages'
"
  response="$(printf '%s' "$payload" | vps1_ssh "$remote_command")" ||
    bl_die "Support reply request failed before the API returned a response."
  [[ "$response" == *$'\n'* ]] || bl_die "Support reply API returned an unexpected response."
  http_status="${response##*$'\n'}"
  response_body="${response%$'\n'*}"

  if [[ "$http_status" != "200" ]]; then
    echo "API response ($http_status):" >&2
    jq . <<<"$response_body" 2>/dev/null || printf '%s\n' "$response_body" >&2
    bl_die "Support reply was not accepted."
  fi

  echo "✔ Reply accepted by the $BL_ENV_LABEL API."
  jq -r '"  message: " + .messageID + "\n  created: " + .createdAt' <<<"$response_body"
}

bl_change_state() {
  local thread_id="$1"
  local new_status="$2"
  bl_require_uuid "$thread_id"
  bl_require_status "$new_status"
  [[ "$new_status" != "all" ]] || bl_die "State cannot be set to 'all'."

  local thread_json owner shop active current
  thread_json="$(bl_thread_json "$thread_id")"
  [[ "$(jq -r 'type' <<<"$thread_json")" == "object" ]] ||
    bl_die "Support thread was not found in $BL_ENV_LABEL."
  active="$(jq -r '.isActive' <<<"$thread_json")"
  [[ "$active" == "true" ]] || bl_die "Closed support threads are read-only; reopening is not implemented."
  current="$(jq -r '.status' <<<"$thread_json")"
  [[ "$current" != "$new_status" ]] || bl_die "Thread is already '$new_status'."
  owner="$(jq -r '.ownerName' <<<"$thread_json")"
  shop="$(jq -r '.shopName + " (" + .shopIdentifier + ")"' <<<"$thread_json")"

  echo
  echo "State transition: $current → $new_status"
  echo "Note: this is a row-scoped SQL update because the API has no explicit state endpoint yet."
  bl_confirm_write "change the thread state to '$new_status'" "$owner" "$shop" "$thread_id" ||
    bl_die "Cancelled (state unchanged)."

  vps1_sqlcmd -b -d "$BL_DATABASE" -Q "
SET NOCOUNT ON;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

DECLARE @ThreadId uniqueidentifier = CAST('$thread_id' AS uniqueidentifier);
DECLARE @NewStatus nvarchar(24) = N'$new_status';

IF NOT EXISTS (
  SELECT 1
  FROM dbo.SupportThread WITH (UPDLOCK, HOLDLOCK)
  WHERE Id = @ThreadId
    AND ClosedAt IS NULL
)
BEGIN
  THROW 51000, 'The active support thread was not found.', 1;
END;

UPDATE dbo.SupportThread
SET
  Status = @NewStatus,
  ClosedAt = CASE WHEN @NewStatus = N'closed' THEN SYSUTCDATETIME() ELSE NULL END,
  UpdatedAt = SYSUTCDATETIME()
WHERE Id = @ThreadId;

COMMIT TRANSACTION;
" >/dev/null
  echo "✔ Thread state changed to '$new_status' in $BL_ENV_LABEL."
}

bl_pick_owner() {
  local owners_json lines selection header
  owners_json="$(bl_owners_json)"
  if [[ "$(jq 'length' <<<"$owners_json")" == "0" ]]; then
    header="No owners have an open support thread in $BL_ENV_LABEL"
  else
    header='OWNER · SHOP · STATE · WAITING · APP'
  fi
  lines="$(
    {
      printf '__BACK__\t← Back to environments\n'
      jq -r '.[] | [
      .activeThreadID,
      (
        .ownerName + " · " + .shopName + " (" + .shopIdentifier + ")" +
        " · " + .activeStatus +
        " · " + (.unansweredOwnerMessages | tostring) + " waiting" +
        (if .appVersion then " · app " + .appVersion else "" end)
      )
    ] | @tsv' <<<"$owners_json"
    }
  )"
  selection="$(printf '%s\n' "$lines" | fzf \
    --height=80% \
    --layout=reverse \
    --border \
    --no-sort \
    --delimiter=$'\t' \
    --with-nth=2 \
    --prompt="$BL_ENV_LABEL · open owner > " \
    --header="$header")" || {
    printf '__BACK__'
    return 0
  }
  printf '%s' "${selection%%$'\t'*}"
}

bl_display_thread_compact_json() {
  local json="$1"
  local latest_support_sequence latest_support_at waiting_count message_number=0
  latest_support_sequence="$(jq '[.messages[] | select(.sender == "support") | .sequenceNumber] | max // 0' <<<"$json")"
  latest_support_at="$(jq -r '[.messages[] | select(.sender == "support")][-1].createdAtUtc // empty' <<<"$json")"
  waiting_count="$(jq --argjson after "$latest_support_sequence" '[.messages[] | select(.sender == "owner" and .sequenceNumber > $after)] | length' <<<"$json")"

  echo
  echo "════════════════════════════════════════════════════════════════"
  printf ' BookingLounge Support · %s\n' "$BL_ENV_LABEL"
  echo "════════════════════════════════════════════════════════════════"
  jq -r '
    "Owner    : " + .ownerName + " <" + .ownerEmail + ">\n" +
    "Shop     : " + .shopName + " (" + .shopIdentifier + ")\n" +
    "State    : " + .status + "\n" +
    "Updated  : " + .updatedAtUtc + " UTC"
  ' <<<"$json"
  echo "────────────────────────────────────────────────────────────────"
  if [[ -n "$latest_support_at" ]]; then
    printf '▶ OWNER MESSAGES SINCE YOUR LAST REPLY · %s\n' "$waiting_count"
    printf '  Last reply: %s UTC\n' "$latest_support_at"
  else
    printf '▶ OWNER MESSAGES IN THIS NEW THREAD · %s\n' "$waiting_count"
  fi

  if ((waiting_count == 0)); then
    echo
    echo "(No owner messages since your last reply.)"
  else
    while IFS= read -r message; do
      ((message_number += 1))
      bl_print_message_card "$message" "$message_number" "$waiting_count"
    done < <(jq -c --argjson after "$latest_support_sequence" '
      [.messages[] | select(.sender == "owner" and .sequenceNumber > $after)][-3:][]
    ' <<<"$json")
  fi
  echo
  echo "────────────────────────────────────────────────────────────────"
}

bl_read_preview_command() {
  local preview_file="$1"
  local commands="$2"
  local expected_keys="$3"
  local result
  result="$(printf '%s\n' "$commands" |
    BL_SUPPORT_PREVIEW_FILE="$preview_file" fzf \
      --layout=reverse \
      --border \
      --no-sort \
      --no-info \
      --no-scrollbar \
      --disabled \
      --ansi \
      --expect="$expected_keys" \
      --prompt='Command number > ' \
      --preview='cat -- "$BL_SUPPORT_PREVIEW_FILE"' \
      --preview-window='up,78%,wrap,border-bottom' \
      --preview-label=' Conversation · Scroll: PgUp/PgDn or Ctrl-U/Ctrl-D ' \
      --bind='ctrl-u:preview-half-page-up,ctrl-d:preview-half-page-down,pgup:preview-page-up,pgdn:preview-page-down')" || return 1
  printf '%s' "${result%%$'\n'*}"
}

bl_choose_state_interactive() {
  local thread_json="$1"
  local command
  bl_create_preview
  BL_FORCE_COLOR=1 bl_display_thread_compact_json "$thread_json" >"$BL_PREVIEW_FILE"
  command="$(bl_read_preview_command \
    "$BL_PREVIEW_FILE" \
    '1 Pending · 2 Engaged · 3 Closed · 0 Back' \
    '1,2,3,0')" || {
    bl_cleanup_preview
    return 1
  }
  bl_cleanup_preview
  case "$command" in
    1) printf 'pending' ;;
    2) printf 'engaged' ;;
    3) printf 'closed' ;;
    *) return 1 ;;
  esac
}

bl_show_full_history_interactive() {
  local thread_json="$1"
  local command
  clear 2>/dev/null || true
  bl_create_preview
  BL_FORCE_COLOR=1 bl_display_thread_json "$thread_json" >"$BL_PREVIEW_FILE"
  command="$(bl_read_preview_command \
    "$BL_PREVIEW_FILE" \
    '1 Conversation · 2 Owners · 3 Environments · 0 Quit' \
    '1,2,3,0')" || {
    bl_cleanup_preview
    return 0
  }
  bl_cleanup_preview
  case "$command" in
    2) BL_NAVIGATION="owners" ;;
    3) BL_NAVIGATION="environment" ;;
    0) BL_NAVIGATION="quit" ;;
  esac
}

bl_interactive_thread() {
  local thread_id="$1"
  local thread_json active command message new_status
  while true; do
    clear 2>/dev/null || true
    thread_json="$(bl_thread_json "$thread_id")"
    active="$(jq -r '.isActive' <<<"$thread_json")"
    [[ "$active" == "true" ]] || {
      BL_NAVIGATION="owners"
      return 0
    }
    bl_create_preview
    BL_FORCE_COLOR=1 bl_display_thread_compact_json "$thread_json" >"$BL_PREVIEW_FILE"

    command="$(bl_read_preview_command \
      "$BL_PREVIEW_FILE" \
      '1 Reply · 2 Change state · 3 History · 4 Owners · 5 Envs · 0 Quit' \
      '1,2,3,4,5,0')" || {
      bl_cleanup_preview
      BL_NAVIGATION="owners"
      return 0
    }
    bl_cleanup_preview

    case "$command" in
      1)
        message="$(bl_read_reply)"
        bl_send_reply "$thread_id" "$message"
        read -r -p "Press Return to refresh the conversation..." _
        ;;
      2)
        new_status="$(bl_choose_state_interactive "$thread_json")" || continue
        bl_change_state "$thread_id" "$new_status"
        if [[ "$new_status" == "closed" ]]; then
          BL_NAVIGATION="owners"
          read -r -p "Thread closed. Press Return to go back to open owners..." _
          return 0
        fi
        read -r -p "Press Return to refresh the conversation..." _
        ;;
      3)
        bl_show_full_history_interactive "$thread_json"
        [[ -z "$BL_NAVIGATION" ]] || return 0
        ;;
      4)
        BL_NAVIGATION="owners"
        return 0
        ;;
      5)
        BL_NAVIGATION="environment"
        return 0
        ;;
      0)
        BL_NAVIGATION="quit"
        return 0
        ;;
    esac
  done
}

bl_interactive() {
  local thread_id
  BL_NAVIGATION=""
  BL_ENV=""

  while true; do
    BL_NAVIGATION=""
    bl_choose_environment || return 0
    bl_configure_environment

    while true; do
      thread_id="$(bl_pick_owner)"
      [[ "$thread_id" != "__BACK__" ]] || break
      bl_interactive_thread "$thread_id"
      case "$BL_NAVIGATION" in
        owners) BL_NAVIGATION="" ;;
        environment) break ;;
        quit) return 0 ;;
      esac
    done
  done
}

bl_parse_args() {
  while (($#)); do
    case "$1" in
      -h | --help | help)
        usage
        exit 0
        ;;
      --env)
        (($# >= 2)) || bl_die "--env requires development/dev or production/prod."
        BL_ENV="$2"
        shift 2
        ;;
      --status)
        (($# >= 2)) || bl_die "--status requires pending, engaged, closed, or all."
        BL_STATUS_FILTER="$2"
        shift 2
        ;;
      --owner)
        (($# >= 2)) || bl_die "--owner requires an owner UUID, email, or shop identifier."
        BL_OWNER_SELECTOR="$2"
        shift 2
        ;;
      --file)
        (($# >= 2)) || bl_die "--file requires a path."
        BL_REPLY_FILE="$2"
        shift 2
        ;;
      --stdin)
        BL_REPLY_STDIN=1
        shift
        ;;
      list | owners | threads | show | reply | state)
        [[ -z "$BL_COMMAND" ]] || bl_die "Only one command can be selected."
        BL_COMMAND="$1"
        shift
        ;;
      --)
        shift
        while (($#)); do
          BL_POSITIONAL+=("$1")
          shift
        done
        ;;
      -*) bl_die "Unknown option: $1" ;;
      *)
        BL_POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

bl_run_command() {
  local owner_id thread_id message state_value
  bl_require_status "$BL_STATUS_FILTER"
  [[ -n "$BL_ENV" ]] || bl_die "Non-interactive commands require --env development|production."
  bl_configure_environment

  case "$BL_COMMAND" in
    list)
      ((${#BL_POSITIONAL[@]} == 0)) || bl_die "list accepts no positional arguments."
      bl_print_active_threads "$BL_STATUS_FILTER"
      ;;
    owners)
      ((${#BL_POSITIONAL[@]} == 0)) || bl_die "owners accepts no positional arguments."
      bl_print_owners
      ;;
    threads)
      [[ -n "$BL_OWNER_SELECTOR" ]] || bl_die "threads requires --owner <owner-guid|email|shop-identifier>."
      owner_id="$(bl_resolve_owner_id "$BL_OWNER_SELECTOR")"
      bl_print_threads "$owner_id"
      ;;
    show)
      ((${#BL_POSITIONAL[@]} == 1)) || bl_die "show requires one thread UUID."
      bl_fetch_and_display_thread "${BL_POSITIONAL[0]}"
      ;;
    reply)
      ((${#BL_POSITIONAL[@]} == 1)) || bl_die "reply requires one thread UUID."
      [[ -z "$BL_REPLY_FILE" || "$BL_REPLY_STDIN" -eq 0 ]] ||
        bl_die "Choose only one reply source: --file or --stdin."
      thread_id="${BL_POSITIONAL[0]}"
      message="$(bl_read_reply)"
      bl_send_reply "$thread_id" "$message"
      bl_fetch_and_display_thread "$thread_id"
      ;;
    state)
      ((${#BL_POSITIONAL[@]} == 2)) || bl_die "state requires a thread UUID and pending|engaged|closed."
      thread_id="${BL_POSITIONAL[0]}"
      state_value="${BL_POSITIONAL[1]}"
      bl_change_state "$thread_id" "$state_value"
      bl_fetch_and_display_thread "$thread_id"
      ;;
    *) bl_die "Unknown command: $BL_COMMAND" ;;
  esac
}

for command in fzf jq python3 sqlcmd ssh curl column; do
  vps1_require_cmd "$command"
done

bl_parse_args "$@"
if [[ -z "$BL_COMMAND" ]]; then
  bl_interactive
else
  bl_run_command
fi
