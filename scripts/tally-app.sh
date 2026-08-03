#!/usr/bin/env bash
set -euo pipefail

TALLY_ROOT="${TALLY_ROOT:-$HOME/projects/tally}"
PROJECT="$TALLY_ROOT/desktop/TallyMacOS.xcodeproj"
SCHEME="TallyMacOS"
DERIVED_DATA="$HOME/Library/Developer/Xcode/DerivedData/TallyMacOS-Forge"
RELEASE_BUNDLE_ID="ro.tnisoft.tally.macos"
DEBUG_BUNDLE_ID="ro.tnisoft.tally.macos.debug"

usage() {
	cat <<EOF
Usage:
  tally-app debug
  tally-app release
  tally-app release --clean

Build and launch the selected Tally macOS configuration. Debug and Release use
separate local preference domains, so switching modes does not mix their state.

Options:
  --clean  Reset all Release client state before launch.
           This does not change the Tally API, SQL Server, or invoice database.
  --help   Show this help.
EOF
}

die() {
	echo "Error: $*" >&2
	exit 1
}

mode=""
clean_release=false

while (($# > 0)); do
	case "$1" in
	debug | release)
		[[ -z "$mode" ]] || die "Choose only one mode: debug or release."
		mode="$1"
		;;
	--clean)
		clean_release=true
		;;
	--help | -h)
		usage
		exit 0
		;;
	*)
		die "Unknown argument: $1. Run 'tally-app --help' for usage."
		;;
	esac
	shift
done

[[ -n "$mode" ]] || die "Choose a mode: 'tally-app debug' or 'tally-app release'."
if [[ "$clean_release" == true && "$mode" != "release" ]]; then
	die "--clean is available only with release mode."
fi

[[ "$(uname -s)" == "Darwin" ]] || die "tally-app only runs on macOS."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required."
[[ -d "$PROJECT" ]] || die "Tally Xcode project not found: $PROJECT"

if [[ "$mode" == "debug" ]]; then
	configuration="Debug"
	bundle_id="$DEBUG_BUNDLE_ID"
else
	configuration="Release"
	bundle_id="$RELEASE_BUNDLE_ID"
fi

echo "Building Tally $configuration..."
xcodebuild \
	-quiet \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration "$configuration" \
	-destination "platform=macOS" \
	-derivedDataPath "$DERIVED_DATA" \
	PRODUCT_BUNDLE_IDENTIFIER="$bundle_id" \
	CODE_SIGNING_ALLOWED=NO \
	build

app_path="$DERIVED_DATA/Build/Products/$configuration/Tally.app"
[[ -d "$app_path" ]] || die "Built app not found: $app_path"

if pgrep -x Tally >/dev/null 2>&1; then
	echo "Closing the running Tally app..."
	osascript -e 'tell application "Tally" to quit' >/dev/null 2>&1 || true
	for _ in 1 2 3 4 5; do
		pgrep -x Tally >/dev/null 2>&1 || break
		sleep 1
	done
	if pgrep -x Tally >/dev/null 2>&1; then
		killall Tally >/dev/null 2>&1 || true
	fi
fi

if [[ "$clean_release" == true ]]; then
	echo "Resetting Tally Release client state..."
	defaults delete "$RELEASE_BUNDLE_ID" >/dev/null 2>&1 || true

	release_paths=(
		"$HOME/Library/Preferences/$RELEASE_BUNDLE_ID.plist"
		"$HOME/Library/Caches/$RELEASE_BUNDLE_ID"
		"$HOME/Library/HTTPStorages/$RELEASE_BUNDLE_ID"
		"$HOME/Library/Saved Application State/$RELEASE_BUNDLE_ID.savedState"
		"$HOME/Library/WebKit/$RELEASE_BUNDLE_ID"
		"$HOME/Library/Application Support/$RELEASE_BUNDLE_ID"
		"$HOME/Library/Containers/$RELEASE_BUNDLE_ID"
		"$HOME/Library/Cookies/$RELEASE_BUNDLE_ID.binarycookies"
	)

	for release_path in "${release_paths[@]}"; do
		if [[ -e "$release_path" || -L "$release_path" ]]; then
			rm -rf -- "$release_path"
		fi
	done
fi

echo "Launching Tally $configuration..."
open -n "$app_path"

if [[ "$clean_release" == true ]]; then
	echo "Tally Release opened with fresh client state; the setup wizard should appear."
else
	echo "Tally $configuration opened with its existing client state."
fi
