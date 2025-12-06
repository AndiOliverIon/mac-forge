#!/usr/bin/env bash
set -euo pipefail

#######################################
# Setup & config
#######################################
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load forge config if present
if [[ -f "$SCRIPT_DIR/forge.sh" ]]; then
  # shellcheck disable=SC1091
  source "$SCRIPT_DIR/forge.sh"
fi

#######################################
# Configuration (overridable)
#######################################

# Root of the perform repo
PERFORM_ROOT="${PERFORM_ROOT:-$HOME/work/ardis-perform}"

# Web project name
PERFORM_WEB_PROJECT="${PERFORM_WEB_PROJECT:-Asms2.Web}"

# Build configuration (first arg or default)
BUILD_CONFIG="${1:-DebugUnitTestLocal}"

# Framework + RID from your error path
FRAMEWORK="${FRAMEWORK:-net8.0}"
RUNTIME_ID="${RUNTIME_ID:-osx-arm64}"

# libgdiplus location:
# 1) use LIBGDIPLUS_PATH if provided (forge.sh or env),
# 2) fallback to standard Homebrew location,
# 3) fallback to asking brew.
DEFAULT_LIBGDIPLUS="/opt/homebrew/opt/mono-libgdiplus/lib/libgdiplus.dylib"
LIBGDIPLUS_PATH="${LIBGDIPLUS_PATH:-$DEFAULT_LIBGDIPLUS}"

if [[ ! -f "$LIBGDIPLUS_PATH" ]]; then
  if command -v brew >/dev/null 2>&1; then
    BREW_PREFIX="$(brew --prefix mono-libgdiplus 2>/dev/null || true)"
    if [[ -n "${BREW_PREFIX:-}" ]] && [[ -f "$BREW_PREFIX/lib/libgdiplus.dylib" ]]; then
      LIBGDIPLUS_PATH="$BREW_PREFIX/lib/libgdiplus.dylib"
    fi
  fi
fi

#######################################
# Derived paths
#######################################
OUTPUT_DIR="$PERFORM_ROOT/$PERFORM_WEB_PROJECT/bin/$BUILD_CONFIG/$FRAMEWORK/$RUNTIME_ID"

#######################################
# Checks
#######################################
echo "== reports-prepare =="
echo "PERFORM_ROOT:      $PERFORM_ROOT"
echo "Web project:       $PERFORM_WEB_PROJECT"
echo "Build config:      $BUILD_CONFIG"
echo "Output dir:        $OUTPUT_DIR"
echo "libgdiplus source: $LIBGDIPLUS_PATH"
echo

if [[ ! -f "$LIBGDIPLUS_PATH" ]]; then
  echo "ERROR: libgdiplus.dylib not found."
  echo "  Expected at: $LIBGDIPLUS_PATH"
  echo "Make sure mono-libgdiplus is installed:"
  echo "  brew install mono-libgdiplus"
  exit 1
fi

if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "ERROR: Output directory does not exist:"
  echo "  $OUTPUT_DIR"
  echo "You probably need to build $PERFORM_WEB_PROJECT first, e.g.:"
  echo "  cd \"$PERFORM_ROOT/$PERFORM_WEB_PROJECT\""
  echo "  dotnet build -c $BUILD_CONFIG"
  exit 1
fi

#######################################
# Copy libgdiplus into output
#######################################
echo "Copying libgdiplus into output directory..."
cp -f "$LIBGDIPLUS_PATH" "$OUTPUT_DIR/libgdiplus.dylib"

echo "Done. Current file:"
ls -l "$OUTPUT_DIR/libgdiplus.dylib"
