#!/usr/bin/env bash
# Builds Support/AppIcon.icns from a square PNG (1024 px recommended).
# With no argument, renders the built-in Lime mark first.
#   scripts/make-icon.sh [path/to/icon.png]
set -euo pipefail
cd "$(dirname "$0")/.."

SOURCE="${1:-}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "$SOURCE" ]]; then
  swift build -q
  SOURCE="$WORK/icon.png"
  "$(swift build --show-bin-path)/Lime" --icon "$SOURCE"
fi

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
for size in 16 32 128 256 512; do
  sips -z $size $size "$SOURCE" --out "$SET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "$SOURCE" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Support/AppIcon.icns
cp "$SOURCE" docs/icon.png
echo "Wrote Support/AppIcon.icns and docs/icon.png"
