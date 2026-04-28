#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FORGE_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${HADES_CERBER_SYNC_CONFIG:-$FORGE_ROOT/configs/hades-cerber-sync.json}"
PREVIEW_LIMIT="${HADES_CERBER_SYNC_PREVIEW_LIMIT:-${PERFORM_SYNC_PREVIEW_LIMIT:-120}}"
LOCAL_BACKUP_ROOT="${HADES_CERBER_SYNC_LOCAL_BACKUP_ROOT:-$HOME/Downloads/temp/hades-cerber-sync-backups}"
CLEAN_CERBER_AFTER_DOWN="${HADES_CERBER_SYNC_CLEAN_CERBER_AFTER_DOWN:-1}"

die() {
	echo "ERROR: $*" >&2
	exit 1
}

require_cmd() {
	command -v "$1" >/dev/null 2>&1 || die "Required command '$1' not found."
}

require_cmd git
require_cmd python3
require_cmd rclone
require_cmd shasum
require_cmd ssh

[[ -f "$CONFIG_FILE" ]] || die "Sync config not found: $CONFIG_FILE"

mode="${1:-}"
profile_arg="${2:-}"

is_help_arg() {
	case "${1:-}" in
	-help | --help | help | -h) return 0 ;;
	*) return 1 ;;
	esac
}

usage() {
	python3 - "$CONFIG_FILE" "$mode" <<'PY'
import json
import sys

config_path = sys.argv[1]
mode = sys.argv[2]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

profiles = config["profiles"]
default = config.get("defaultProfile", "")

command = {
    "up": "h2c",
    "down": "c2h",
    "preview-up": "h2c-preview",
    "preview-down": "c2h-preview",
}.get(mode, "h2c")

print("Hades/Cerber manual sync")
print()
print("Commands:")
print("  h2c [profile]          Hades -> Cerber, after preparing Cerber from the profile base branch")
print("  c2h [profile]          Cerber -> Hades, then clean Cerber when the profile asks for it")
print("  h2c-preview [profile]  Show Hades working-tree changes that would go to Cerber")
print("  c2h-preview [profile]  Show Cerber working-tree changes that would come to Hades")
print()
print(f"Current command: {command}")
print(f"Default profile: {default}")
print()
print("Profiles:")
for name, profile in profiles.items():
    marker = " (default)" if name == default else ""
    description = profile.get("description", "")
    base = profile.get("baseBranch", "")
    mac_root = profile["macRoot"]
    target = f'{profile["rcloneRemote"]}:{profile["winRoot"]}'
    print(f"  {name}{marker}")
    if description:
        print(f"    {description}")
    print(f"    Hades:  {mac_root}")
    print(f"    Cerber: {target}")
    if base:
        print(f"    Base:   origin/{base}")
    print()
print("Examples:")
print("  h2c perf")
print("  c2h perf")
print("  h2c-preview perf228")
PY
}

if [[ -z "$mode" ]] || is_help_arg "$mode" || is_help_arg "$profile_arg"; then
	usage
	exit 0
fi

case "$mode" in
up | down | preview-up | preview-down | status) ;;
*)
	usage
	exit 1
	;;
esac

resolve_profile() {
	local requested="$1"
	python3 - "$CONFIG_FILE" "$requested" "$PWD" <<'PY'
import json
import os
import sys

config_path, requested, cwd = sys.argv[1], sys.argv[2], os.path.realpath(sys.argv[3])

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

profiles = config["profiles"]

if requested:
    if requested not in profiles:
        raise SystemExit(f"Unknown sync profile: {requested}")
    print(requested)
    raise SystemExit(0)

matches = []
for name, profile in profiles.items():
    root = os.path.realpath(os.path.expanduser(profile["macRoot"]))
    if cwd == root or cwd.startswith(root + os.sep):
        matches.append((len(root), name))

if matches:
    print(sorted(matches, reverse=True)[0][1])
else:
    print(config.get("defaultProfile", ""))
PY
}

profile_name="$(resolve_profile "$profile_arg")"
[[ -n "$profile_name" ]] || die "No sync profile selected."

profile_exports="$(
	python3 - "$CONFIG_FILE" "$profile_name" <<'PY'
import json
import shlex
import sys

config_path, profile_name = sys.argv[1], sys.argv[2]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

profile = config["profiles"][profile_name]

values = {
    "PROFILE_NAME": profile_name,
    "PROFILE_DESCRIPTION": profile.get("description", ""),
    "MAC_ROOT": profile["macRoot"],
    "WIN_PATH": profile["winRoot"].rstrip("/"),
    "RCLONE_REMOTE": profile["rcloneRemote"],
    "SSH_HOST": profile["sshHost"],
    "BASE_BRANCH": profile.get("baseBranch", ""),
    "AFTER_H2C": profile.get("afterH2c", ""),
    "AFTER_C2H": profile.get("afterC2h", ""),
}

for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)"
eval "$profile_exports"

WIN_ROOT="${RCLONE_REMOTE}:${WIN_PATH}"
WIN_GIT_ROOT="$WIN_PATH"
REMOTE_BACKUP_ROOT="${RCLONE_REMOTE}:C:/work/.rclone-backups/${PROFILE_NAME}"
REMOTE_H2C_BASELINE_PATH=".git/info/hades-cerber-h2c-baseline.tsv"

[[ -d "$MAC_ROOT" ]] || die "macOS project folder not found for profile '$PROFILE_NAME': $MAC_ROOT"

status_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-status.XXXXXX")"
delta_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-delta.XXXXXX")"
actions_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-actions.XXXXXX")"
filtered_actions_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-filtered-actions.XXXXXX")"
hades_actions_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-hades-actions.XXXXXX")"
local_only_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-local-only.XXXXXX")"
always_h2c_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-always-h2c.XXXXXX")"
always_h2c_dir_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-always-h2c-dirs.XXXXXX")"
h2c_paths_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-h2c-paths.XXXXXX")"
remote_h2c_paths_file="$(mktemp "${TMPDIR:-/tmp}/hades-cerber-remote-h2c-paths.XXXXXX")"
trap 'rm -f "$status_file" "$delta_file" "$actions_file" "$filtered_actions_file" "$hades_actions_file" "$local_only_file" "$always_h2c_file" "$always_h2c_dir_file" "$h2c_paths_file" "$remote_h2c_paths_file"' EXIT

python3 - "$CONFIG_FILE" "$profile_name" >"$local_only_file" <<'PY'
import json
import sys

config_path, profile_name = sys.argv[1], sys.argv[2]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

paths = []
paths.extend(config.get("alwaysH2cPaths", []))
paths.extend(config.get("alwaysH2cDirectories", []))
paths.extend(config["profiles"][profile_name].get("localOnlyIgnorePaths", []))
paths.extend(config["profiles"][profile_name].get("alwaysH2cPaths", []))
paths.extend(config["profiles"][profile_name].get("alwaysH2cDirectories", []))

for path in dict.fromkeys(paths):
    print(path.replace("\\", "/").strip("/"))
PY

python3 - "$CONFIG_FILE" "$profile_name" >"$always_h2c_file" <<'PY'
import json
import sys

config_path, profile_name = sys.argv[1], sys.argv[2]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

paths = []
paths.extend(config.get("alwaysH2cPaths", []))
paths.extend(config["profiles"][profile_name].get("alwaysH2cPaths", []))

for path in dict.fromkeys(paths):
    print(path.replace("\\", "/").strip("/"))
PY

python3 - "$CONFIG_FILE" "$profile_name" >"$always_h2c_dir_file" <<'PY'
import json
import sys

config_path, profile_name = sys.argv[1], sys.argv[2]

with open(config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

paths = []
paths.extend(config.get("alwaysH2cDirectories", []))
paths.extend(config["profiles"][profile_name].get("alwaysH2cDirectories", []))

for path in dict.fromkeys(paths):
    print(path.replace("\\", "/").strip("/"))
PY

local_branch() {
	git -C "$MAC_ROOT" rev-parse --abbrev-ref HEAD
}

remote_branch() {
	ssh "$SSH_HOST" "git -C $WIN_GIT_ROOT rev-parse --abbrev-ref HEAD" | tr -d '\r'
}

assert_matching_branches() {
	local mac_branch cerber_branch
	mac_branch="$(local_branch)"
	cerber_branch="$(remote_branch)"

	echo "Profile:       $PROFILE_NAME"
	echo "macOS branch:  $mac_branch"
	echo "Cerber branch: $cerber_branch"

	[[ "$mac_branch" == "$cerber_branch" ]] || die "Branch mismatch. Switch both worktrees to the same branch first."
}

local_status_file() {
	local output="$1"
	git -C "$MAC_ROOT" status --porcelain=v1 --untracked-files=all >"$output"
}

local_delta_file() {
	local output="$1"
	git -C "$MAC_ROOT" diff --name-status --find-renames "origin/$BASE_BRANCH...HEAD" >"$output"
}

remote_status_file() {
	local output="$1"
	ssh "$SSH_HOST" "git -C $WIN_GIT_ROOT status --porcelain=v1 --untracked-files=all" | tr -d '\r' >"$output"
}

remote_delta_file() {
	local output="$1"
	ssh "$SSH_HOST" "git -C $WIN_GIT_ROOT diff --name-status --find-renames origin/$BASE_BRANCH...HEAD" | tr -d '\r' >"$output"
}

parse_changes_file() {
	local delta_path="$1"
	local status_path="$2"
	local actions_path="$3"
	local ignores_path="$4"

	python3 - "$delta_path" "$status_path" "$actions_path" "$ignores_path" <<'PY'
import sys

delta_path, status_path, actions_path, ignores_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
actions = []

with open(ignores_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    ignored = {line.strip().replace("\\", "/").strip("/") for line in f if line.strip()}

def is_ignored(path):
    normalized = path.replace("\\", "/").strip("/")
    return any(normalized == item or normalized.startswith(item + "/") for item in ignored)

def add(action, path):
    if not is_ignored(path):
        actions.append((action, path))

with open(delta_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue

        parts = line.split("\t")
        status = parts[0]

        if status.startswith("R"):
            if len(parts) != 3:
                raise SystemExit(f"Could not parse rename path: {line}")
            add("delete", parts[1])
            add("copy", parts[2])
            continue

        if len(parts) != 2:
            raise SystemExit(f"Could not parse changed path: {line}")

        path = parts[1]
        if status.startswith("D"):
            add("delete", path)
        else:
            add("copy", path)

with open(status_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue

        status = line[:2]
        path = line[3:]

        if "U" in status or status in {"AA", "DD"}:
            raise SystemExit(f"Unmerged path must be resolved before sync: {path}")

        if status.startswith("R") or status.endswith("R"):
            if " -> " not in path:
                raise SystemExit(f"Could not parse rename path: {path}")
            old, new = path.split(" -> ", 1)
            add("delete", old)
            add("copy", new)
            continue

        if status == "??":
            add("copy", path)
            continue

        if "D" in status:
            add("delete", path)
            continue

        add("copy", path)

deduped = {}
for action, path in actions:
    deduped[path] = action

with open(actions_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    for path, action in deduped.items():
        f.write(f"{action}\t{path}\n")
PY
}

build_actions() {
	local side="$1"
	local status_path="$2"
	local actions_path="$3"

	case "$side" in
	hades)
		local_delta_file "$delta_file"
		local_status_file "$status_path"
		;;
	cerber)
		remote_delta_file "$delta_file"
		remote_status_file "$status_path"
		;;
	*) die "Unknown action source: $side" ;;
	esac

	parse_changes_file "$delta_file" "$status_path" "$actions_path" "$local_only_file"
}

print_actions_report() {
	local actions_path="$1"
	local copy_count delete_count change_count
	copy_count="$(awk -F '\t' '$1 == "copy" { count++ } END { print count + 0 }' "$actions_path")"
	delete_count="$(awk -F '\t' '$1 == "delete" { count++ } END { print count + 0 }' "$actions_path")"
	change_count=$((copy_count + delete_count))

	echo "Git-status preview summary:"
	echo "  Files to copy/update:      $copy_count"
	echo "  Files to delete on target: $delete_count"
	echo

	if ((change_count == 0)); then
		echo "No working-tree changes to sync."
		return 0
	fi

	echo "Actions, first $PREVIEW_LIMIT of $change_count:"
	awk -F '\t' -v limit="$PREVIEW_LIMIT" '
		{
			printf "%s %s\n", $1, $2
			count++
			if (count >= limit) {
				exit
			}
		}
	' "$actions_path"

	if ((change_count > PREVIEW_LIMIT)); then
		echo
		echo "... $((change_count - PREVIEW_LIMIT)) more actions hidden."
		echo "Set HADES_CERBER_SYNC_PREVIEW_LIMIT to show more."
	fi
}

print_always_h2c_report() {
	if [[ ! -s "$always_h2c_file" && ! -s "$always_h2c_dir_file" ]]; then
		return 0
	fi

	echo
	echo "Always copied Hades -> Cerber:"
	if [[ -s "$always_h2c_file" ]]; then
		sed 's/^/  copy file /' "$always_h2c_file"
	fi
	if [[ -s "$always_h2c_dir_file" ]]; then
		sed 's/^/  copy dir  /' "$always_h2c_dir_file"
	fi
}

remote_path() {
	local path="$1"
	printf '%s/%s' "$WIN_ROOT" "$path"
}

local_path() {
	local path="$1"
	printf '%s/%s' "$MAC_ROOT" "$path"
}

backup_remote_path() {
	local backup_dir="$1"
	local path="$2"
	printf '%s/%s' "$backup_dir" "$path"
}

backup_local_path() {
	local backup_dir="$1"
	local path="$2"
	printf '%s/%s' "$backup_dir" "$path"
}

backup_and_delete() {
	local target="$1"
	local backup="$2"

	if rclone lsl "$target" >/dev/null 2>&1; then
		rclone moveto "$target" "$backup" --create-empty-src-dirs --log-level INFO
	else
		echo "Target already absent: $target"
	fi
}

apply_actions() {
	local direction="$1"
	local actions_path="$2"
	local backup_dir="$3"
	local action path

	echo
	echo "Direction: $direction"
	echo "Source:    $([[ "$direction" == "hades-to-cerber" ]] && echo "$MAC_ROOT" || echo "$WIN_ROOT")"
	echo "Target:    $([[ "$direction" == "hades-to-cerber" ]] && echo "$WIN_ROOT" || echo "$MAC_ROOT")"
	echo "Backup:    $backup_dir"
	echo

	while IFS=$'\t' read -r action path; do
		[[ -n "${action:-}" && -n "${path:-}" ]] || continue

		case "$direction:$action" in
		"hades-to-cerber:copy")
			rclone copyto "$(local_path "$path")" "$(remote_path "$path")" --backup-dir "$backup_dir" --log-level INFO
			;;
		"hades-to-cerber:delete")
			backup_and_delete "$(remote_path "$path")" "$(backup_remote_path "$backup_dir" "$path")"
			;;
		"cerber-to-hades:copy")
			rclone copyto "$(remote_path "$path")" "$(local_path "$path")" --backup-dir "$backup_dir" --log-level INFO
			;;
		"cerber-to-hades:delete")
			backup_and_delete "$(local_path "$path")" "$(backup_local_path "$backup_dir" "$path")"
			;;
		*)
			die "Unsupported action: $direction $action $path"
			;;
		esac
	done <"$actions_path"
}

apply_always_h2c_paths() {
	local path

	if [[ ! -s "$always_h2c_file" && ! -s "$always_h2c_dir_file" ]]; then
		return 0
	fi

	echo
	echo "Promoting Hades local files to Cerber..."

	while IFS= read -r path; do
		[[ -n "$path" ]] || continue
		[[ -f "$(local_path "$path")" ]] || die "Always-copy source file does not exist: $(local_path "$path")"
		rclone copyto "$(local_path "$path")" "$(remote_path "$path")" --log-level INFO
	done <"$always_h2c_file"

	while IFS= read -r path; do
		[[ -n "$path" ]] || continue
		[[ -d "$(local_path "$path")" ]] || die "Always-copy source directory does not exist: $(local_path "$path")"
		rclone copy "$(local_path "$path")" "$(remote_path "$path")" --exclude ".DS_Store" --log-level INFO
	done <"$always_h2c_dir_file"
}

write_baseline_from_actions() {
	local source_actions="$1"
	local output_baseline="$2"
	local action path hash

	: >"$output_baseline"

	while IFS=$'\t' read -r action path; do
		[[ "$action" == "copy" && -n "${path:-}" ]] || continue
		[[ -f "$(local_path "$path")" ]] || continue

		hash="$(shasum -a 256 "$(local_path "$path")" | awk '{ print $1 }')"
		printf '%s\t%s\n' "$hash" "$path" >>"$output_baseline"
	done <"$source_actions"
}

write_h2c_baseline() {
	write_baseline_from_actions "$actions_file" "$h2c_paths_file"

	rclone copyto "$h2c_paths_file" "$(remote_path "$REMOTE_H2C_BASELINE_PATH")" --log-level INFO
}

write_current_hades_baseline() {
	local_delta_file "$delta_file"
	local_status_file "$status_file"
	parse_changes_file "$delta_file" "$status_file" "$hades_actions_file" "$local_only_file"
	write_baseline_from_actions "$hades_actions_file" "$remote_h2c_paths_file"
}

filter_hades_origin_actions() {
	local input_actions="$1"
	local output_actions="$2"

	if ! rclone cat "$(remote_path "$REMOTE_H2C_BASELINE_PATH")" >"$remote_h2c_paths_file" 2>/dev/null; then
		write_current_hades_baseline
	fi

	if [[ ! -s "$remote_h2c_paths_file" ]]; then
		cp "$input_actions" "$output_actions"
		return 0
	fi

	python3 - "$input_actions" "$output_actions" "$remote_h2c_paths_file" "$SSH_HOST" "$WIN_GIT_ROOT" <<'PY'
import subprocess
import sys

actions_path, output_path, baseline_path, ssh_host, win_git_root = sys.argv[1:]

baseline = {}
with open(baseline_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue
        expected_hash, path = line.split("\t", 1)
        baseline[path.replace("\\", "/").strip("/")] = expected_hash.lower()

def ps_single_quote(value):
    return "'" + value.replace("'", "''") + "'"

def remote_hash(path):
    full_path = f"{win_git_root.rstrip('/')}/{path}"
    command = (
        "$p = " + ps_single_quote(full_path) + "; "
        "if (Test-Path -LiteralPath $p -PathType Leaf) { "
        "(Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLowerInvariant() "
        "}"
    )
    result = subprocess.run(
        ["ssh", ssh_host, "powershell", "-NoProfile", "-Command", command],
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        return None
    value = result.stdout.strip().lower()
    return value or None

kept = []
skipped = 0

with open(actions_path, "r", encoding="utf-8", errors="surrogateescape") as f:
    for raw in f:
        line = raw.rstrip("\n")
        if not line:
            continue

        action, path = line.split("\t", 1)
        normalized = path.replace("\\", "/").strip("/")

        if action == "copy" and normalized in baseline:
            current_hash = remote_hash(normalized)
            if current_hash == baseline[normalized]:
                skipped += 1
                continue

        kept.append((action, path))

with open(output_path, "w", encoding="utf-8", errors="surrogateescape") as f:
    for action, path in kept:
        f.write(f"{action}\t{path}\n")

if skipped:
    print(f"Skipped unchanged Hades-origin paths: {skipped}")
PY
}

prepare_cerber_for_up() {
	local branch="$1"

	[[ -n "$BASE_BRANCH" ]] || die "Profile '$PROFILE_NAME' has no baseBranch configured."

	echo
	echo "Preparing Cerber from origin/$BASE_BRANCH..."
	ssh "$SSH_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -Command -" <<EOF
\$ErrorActionPreference = 'Stop'
\$repo = '$WIN_GIT_ROOT'
\$branch = '$branch'
\$baseBranch = '$BASE_BRANCH'

Set-Location -LiteralPath \$repo
\$env:GIT_TERMINAL_PROMPT = '0'
\$env:GIT_SSH_COMMAND = 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new'

\$status = git status --porcelain=v1 --untracked-files=all
if (\$status) {
    Write-Host 'Cerber is not clean. Clean or reset the VM checkout first, then run h2c again.'
    git status --short
    exit 42
}

git fetch origin "\${baseBranch}:refs/remotes/origin/\${baseBranch}"
git checkout -B \$branch "origin/\$baseBranch"
git pull --ff-only origin \$baseBranch
EOF
}

perform_vs_localize() {
	[[ "$AFTER_H2C" == "perform-vs-localize" ]] || return 0

	echo
	echo "Applying Cerber-local Visual Studio PERFORM adjustments..."
	ssh "$SSH_HOST" "powershell -NoProfile -ExecutionPolicy Bypass -Command -" <<EOF
\$ErrorActionPreference = 'Stop'
\$repo = '$WIN_GIT_ROOT'
Set-Location -LiteralPath \$repo

if (Test-Path -LiteralPath '.\Asms2.Web.sln') {
    Copy-Item -LiteralPath '.\Asms2.Web.sln' -Destination '.\Asms2.Web.cerber.sln' -Force
    dotnet sln '.\Asms2.Web.cerber.sln' remove '.\docker-compose.dcproj' 2>\$null
}

\$projectFiles = @(
    'Asms2.Web\Asms2.Web.csproj',
    'Ardis.Checklist.Worker\Ardis.Checklist.Worker.csproj'
)

foreach (\$projectFile in \$projectFiles) {
    if (-not (Test-Path -LiteralPath \$projectFile)) {
        continue
    }

    [xml]\$project = Get-Content -LiteralPath \$projectFile
    \$changed = \$false

    foreach (\$node in @(\$project.SelectNodes('//DockerDefaultTargetOS') + \$project.SelectNodes('//DockerComposeProjectPath'))) {
        if (\$null -ne \$node) {
            [void]\$node.ParentNode.RemoveChild(\$node)
            \$changed = \$true
        }
    }

    foreach (\$node in @(\$project.SelectNodes("//PackageReference[@Include='Microsoft.VisualStudio.Azure.Containers.Tools.Targets']"))) {
        if (\$null -ne \$node) {
            [void]\$node.ParentNode.RemoveChild(\$node)
            \$changed = \$true
        }
    }

    if (\$changed) {
        \$project.Save((Resolve-Path -LiteralPath \$projectFile))
    }
}

\$webProjectFile = 'Asms2.Web\Asms2.Web.csproj'
if (Test-Path -LiteralPath \$webProjectFile) {
    \$webProjectContent = Get-Content -LiteralPath \$webProjectFile -Raw
    if (\$webProjectContent -notmatch 'LOCAL_OVERRIDES_BEGIN: local-csproj-compile') {
        \$localOverrideCompileBlock = @'
<!-- LOCAL_OVERRIDES_BEGIN: local-csproj-compile -->
<ItemGroup>
    <Compile Remove="..\\local-overrides\\**\\*.cs" />
</ItemGroup>

<ItemGroup Condition="Exists('..\\local-overrides')">
    <Compile Include="..\\local-overrides\\**\\*.cs" />
</ItemGroup>
<!-- LOCAL_OVERRIDES_END: local-csproj-compile -->
'@
        \$marker = '<!-- AFTER TARGET SCRIPTS -->'
        \$markerIndex = \$webProjectContent.IndexOf(\$marker)
        if (\$markerIndex -lt 0) {
            throw "Could not find marker in \$(\$webProjectFile): \$marker"
        }

        \$webProjectContent = \$webProjectContent.Insert(\$markerIndex, \$localOverrideCompileBlock + [Environment]::NewLine + '  ')
        Set-Content -LiteralPath \$webProjectFile -Value \$webProjectContent -NoNewline
    }
}

\$excludeFile = '.git\info\exclude'
\$entries = @(
    'Asms2.Web.cerber.sln',
    'Asms2.Web.cerber.slnf'
)

foreach (\$entry in \$entries) {
    \$content = if (Test-Path -LiteralPath \$excludeFile) { Get-Content -LiteralPath \$excludeFile } else { @() }
    if (\$content -notcontains \$entry) {
        Add-Content -LiteralPath \$excludeFile -Value \$entry
    }
}
EOF
}

clean_cerber_worktree() {
	if [[ "$AFTER_C2H" != "clean" || "$CLEAN_CERBER_AFTER_DOWN" != "1" ]]; then
		echo "Cerber cleanup skipped."
		return 0
	fi

	echo
	echo "Cleaning Cerber working tree..."
	ssh "$SSH_HOST" "git -C $WIN_GIT_ROOT reset --hard && git -C $WIN_GIT_ROOT clean -fd"
}

stamp="$(date +%Y%m%d-%H%M%S)"

case "$mode" in
status)
	assert_matching_branches
	echo
	rclone lsf "${RCLONE_REMOTE}:C:/work" --max-depth 1
	;;

preview-up)
	echo "Profile:      $PROFILE_NAME"
	echo "macOS branch: $(local_branch)"
	echo "Base branch:  origin/$BASE_BRANCH"
	echo "Cerber will be prepared from the base branch before h2c copies these changes."
	echo
	build_actions "hades" "$status_file" "$actions_file"
	print_actions_report "$actions_file"
	print_always_h2c_report
	;;

up)
	mac_branch="$(local_branch)"
	echo "Profile:      $PROFILE_NAME"
	echo "macOS branch: $mac_branch"
	echo "Base branch:  origin/$BASE_BRANCH"
	prepare_cerber_for_up "$mac_branch"
	assert_matching_branches
	build_actions "hades" "$status_file" "$actions_file"
	print_actions_report "$actions_file"
	apply_actions "hades-to-cerber" "$actions_file" "$REMOTE_BACKUP_ROOT/to-cerber-$stamp"
	apply_always_h2c_paths
	write_h2c_baseline
	perform_vs_localize
	;;

preview-down)
	assert_matching_branches
	mkdir -p "$LOCAL_BACKUP_ROOT/$PROFILE_NAME"
	build_actions "cerber" "$status_file" "$actions_file"
	filter_hades_origin_actions "$actions_file" "$filtered_actions_file"
	print_actions_report "$filtered_actions_file"
	;;

down)
	assert_matching_branches
	mkdir -p "$LOCAL_BACKUP_ROOT/$PROFILE_NAME"
	build_actions "cerber" "$status_file" "$actions_file"
	filter_hades_origin_actions "$actions_file" "$filtered_actions_file"
	print_actions_report "$filtered_actions_file"
	apply_actions "cerber-to-hades" "$filtered_actions_file" "$LOCAL_BACKUP_ROOT/$PROFILE_NAME/from-cerber-$stamp"
	clean_cerber_worktree
	;;
esac
