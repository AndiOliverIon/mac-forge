#!/usr/bin/env bash
set -euo pipefail

die() { echo "✗ $*" >&2; exit 1; }

usage() {
	cat <<'EOF'
Usage:
  work-today            Declared Jira worklog time for today, grouped by project.
  work-today --log N    Same, for the day N days in the past (1 = yesterday, 2 = two days ago, ...).
  work-today --span N   Cover today plus the previous N days, each day segmented separately,
                        with a combined total. --span 1 = yesterday and today so far.

--log and --span combine: --log picks the most recent day, --span extends the range further back.

Reports every Jira task you logged work on, across all projects, how much time you declared
on each, per-project subtotals, per-day totals and a grand total.

Aliases: wt, work-today
EOF
}

days_back=0
span=0
while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	--log)
		[[ $# -ge 2 ]] || die "--log needs a number of days"
		days_back="$2"
		shift 2
		;;
	--log=*)
		days_back="${1#*=}"
		shift
		;;
	--span)
		[[ $# -ge 2 ]] || die "--span needs a number of days"
		span="$2"
		shift 2
		;;
	--span=*)
		span="${1#*=}"
		shift
		;;
	*)
		usage >&2
		die "Unknown argument: $1"
		;;
	esac
done

[[ "$days_back" =~ ^[0-9]+$ ]] || die "--log value must be a non-negative integer (got '$days_back')"
[[ "$span" =~ ^[0-9]+$ ]] || die "--span value must be a non-negative integer (got '$span')"

if command -v twg >/dev/null 2>&1; then
	TWG="twg"
elif [[ -x "$HOME/.local/bin/twg" ]]; then
	TWG="$HOME/.local/bin/twg"
else
	die "twg CLI not found (install it or add ~/.local/bin to PATH)"
fi

command -v python3 >/dev/null 2>&1 || die "python3 missing"

TWG="$TWG" python3 - "$days_back" "$span" <<'PY'
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None

TWG = os.environ["TWG"]
days_back = int(sys.argv[1])
span = int(sys.argv[2])

# ANSI colors (disabled when output is not a terminal).
if sys.stdout.isatty():
    BOLD, DIM, CYAN, GREEN, YELLOW, RESET = "\033[1m", "\033[2m", "\033[36m", "\033[32m", "\033[33m", "\033[0m"
else:
    BOLD = DIM = CYAN = GREEN = YELLOW = RESET = ""


def twg_json(args):
    cmd = [TWG, *args, "--output", "json", "--output-summary", "none"]
    try:
        out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    except FileNotFoundError:
        sys.exit(f"\u2717 twg not found: {TWG}")
    except subprocess.CalledProcessError as e:
        sys.exit(f"\u2717 twg failed: {' '.join(args)}\n{e.stderr.strip()}")
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        sys.exit(f"\u2717 could not parse twg JSON for: {' '.join(args)}")


# Resolve the authenticated user and their timezone (no hardcoded account).
me = twg_json(["whoami"]).get("data", {})
account_id = me.get("accountId")
zone = me.get("zoneinfo") or "UTC"
if not account_id:
    sys.exit("\u2717 could not resolve the current Jira account (twg whoami)")

tz = ZoneInfo(zone) if ZoneInfo else None
now = datetime.now(tz)
anchor = (now - timedelta(days=days_back)).date()
start = anchor - timedelta(days=span)
# Days covered, oldest first (reads as a timeline ending at the anchor day).
day_count = (anchor - start).days + 1
days = [start + timedelta(days=i) for i in range(day_count)]


def day_label(d):
    delta = (now.date() - d).days
    if delta == 0:
        when = "today"
    elif delta == 1:
        when = "yesterday"
    else:
        when = f"{delta} days ago"
    return f"{d.strftime('%A, %Y-%m-%d')} ({when})"


def parse_started(value):
    # e.g. 2026-08-17T00:25:29.921+0200
    try:
        dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%S.%f%z")
    except ValueError:
        try:
            dt = datetime.strptime(value, "%Y-%m-%dT%H:%M:%S%z")
        except ValueError:
            return None
    return dt.astimezone(tz) if tz else dt


def worklogs_for(issue):
    wl = issue.get("worklog") or {}
    logs = wl.get("worklogs", [])
    total = wl.get("total", len(logs))
    # Refetch when the inline worklog set was truncated by Jira pagination.
    if total > len(logs):
        full = twg_json(["jira", "workitem", "get", issue["key"], "--fields", "worklog"])
        data = full.get("data", full)
        if isinstance(data, list):
            data = data[0] if data else {}
        logs = ((data.get("worklog") or {}).get("worklogs")) or logs
    return logs


if start == anchor:
    date_clause = 'worklogDate = "%s"' % anchor.isoformat()
else:
    date_clause = 'worklogDate >= "%s" AND worklogDate <= "%s"' % (start.isoformat(), anchor.isoformat())
jql = (
    "worklogAuthor = currentUser() AND %s "
    "ORDER BY project ASC, key ASC" % date_clause
)
result = twg_json(["jira", "workitem", "query", "--jql", jql, "--fields", "summary,project,worklog", "--limit", "500"])
issues = (result.get("data", {}) or {}).get("issues") or result.get("issues") or []

# Aggregate my declared seconds per issue, per day, grouped by project.
# by_day[date] -> {pkey -> {"name":..., "issues": {key: {"summary":..., "seconds":...}}}}
by_day = {d: {} for d in days}
in_range = set(days)
for issue in issues:
    key = issue.get("key")
    summary = issue.get("summary", "")
    proj = issue.get("project", {}) or {}
    pkey = proj.get("key", "?")
    pname = proj.get("name", pkey)

    for wl in worklogs_for(issue):
        author = (wl.get("author") or {}).get("accountId")
        if author != account_id:
            continue
        started = parse_started(wl.get("started", ""))
        if started is None or started.date() not in in_range:
            continue
        seconds = int(wl.get("timeSpentSeconds", 0))
        if seconds <= 0:
            continue
        projects = by_day[started.date()]
        p = projects.setdefault(pkey, {"name": pname, "issues": {}})
        entry = p["issues"].setdefault(key, {"summary": summary, "seconds": 0})
        entry["seconds"] += seconds


def fmt(seconds):
    h, m = divmod(seconds // 60, 60)
    return f"{h}h {m:02d}m"


def render_day(projects):
    """Print one day's project-grouped breakdown; return (seconds, task_count)."""
    day_seconds = 0
    day_tasks = 0
    all_keys = [k for p in projects.values() for k in p["issues"]]
    key_w = max((len(k) for k in all_keys), default=8)
    for pkey in sorted(projects):
        p = projects[pkey]
        print(f"{CYAN}{BOLD}{p['name']} ({pkey}){RESET}")
        psec = 0
        for key in sorted(p["issues"]):
            e = p["issues"][key]
            psec += e["seconds"]
            day_tasks += 1
            summary = e["summary"]
            if len(summary) > 60:
                summary = summary[:57] + "..."
            print(f"  {key.ljust(key_w)}  {summary.ljust(60)}  {GREEN}{fmt(e['seconds']).rjust(8)}{RESET}")
        day_seconds += psec
        print(f"  {DIM}{'subtotal'.rjust(key_w + 62)}{RESET}  {YELLOW}{fmt(psec).rjust(8)}{RESET}")
        print()
    return day_seconds, day_tasks


multi = len(days) > 1
print()
if multi:
    print(f"{BOLD}Worklog from {start.isoformat()} to {anchor.isoformat()} ({len(days)} days){RESET}")

grand_seconds = 0
grand_tasks = 0
active_days = 0

for d in days:
    projects = by_day[d]
    print()
    print(f"{BOLD}── {day_label(d)}{RESET}")
    print()
    if not projects:
        print(f"{DIM}No time declared.{RESET}")
        print()
        continue
    day_seconds, day_tasks = render_day(projects)
    grand_seconds += day_seconds
    grand_tasks += day_tasks
    active_days += 1
    workdays = day_seconds / 28800  # Jira default: 1d = 8h
    if multi:
        print(
            f"{BOLD}Day total: {fmt(day_seconds)}{RESET}  "
            f"{DIM}(= {workdays:.2f}d @8h){RESET}  "
            f"{day_tasks} task(s) in {len(projects)} project(s)"
        )
        print()

if grand_seconds == 0:
    if not multi:
        pass  # single empty day already reported above
    else:
        print(f"{DIM}No time declared in this range.{RESET}")
        print()
    sys.exit(0)

if multi:
    workdays = grand_seconds / 28800
    print(f"{DIM}{'─' * 60}{RESET}")
    print(
        f"{BOLD}Grand total: {fmt(grand_seconds)}{RESET}  "
        f"{DIM}(= {workdays:.2f}d @8h){RESET}  "
        f"across {grand_tasks} task(s), {active_days} active day(s)"
    )
    print()
else:
    workdays = grand_seconds / 28800
    proj_count = len(by_day[anchor])
    print(
        f"{BOLD}Total: {fmt(grand_seconds)}{RESET}  "
        f"{DIM}(= {workdays:.2f}d @8h){RESET}  "
        f"across {grand_tasks} task(s) in {proj_count} project(s)"
    )
    print()
PY
