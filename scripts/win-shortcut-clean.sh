#!/usr/bin/env bash
set -euo pipefail

DIR="$HOME/Applications (Parallels)"
DRY_RUN=false   # change to false when you're confident

# Only keep this one
keep=(
  "Visual Studio.app"
)

if [ ! -d "$DIR" ]; then
  echo "Directory not found: $DIR"
  exit 0
fi

echo "Scanning: $DIR"
echo

# Look into GUID subfolder(s) too (like {7d1d...} Applications.localized)
find "$DIR" -maxdepth 2 -mindepth 1 -type d -name "*.app" | sort | while read -r app; do
  name="$(basename "$app")"

  keep_it=false
  for k in "${keep[@]}"; do
    if [ "$name" = "$k" ]; then
      keep_it=true
      break
    fi
  done

  if [ "$keep_it" = true ]; then
    echo "Keeping:    $name"
  else
    if [ "$DRY_RUN" = true ]; then
      echo "[DRY RUN] Would remove: $name"
    else
      echo "Removing:   $name"
      rm -rf "$app"
    fi
  fi
done
