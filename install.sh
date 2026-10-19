#!/usr/bin/env bash
# Installs the latest Lime: File Converter release.
#   curl -fsSL https://raw.githubusercontent.com/joseandresborrerorodz/lime/main/install.sh | bash
set -euo pipefail

REPO="joseandresborrerorodz/lime"
URL="https://github.com/$REPO/releases/latest/download/Lime.zip"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Lime runs on macOS only." >&2
  exit 1
fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if (( major < 13 )); then
  echo "Lime needs macOS 13 or later (this Mac has $(sw_vers -productVersion))." >&2
  exit 1
fi

DEST=/Applications
[[ -w "$DEST" ]] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Downloading Lime…"
curl -fsSL "$URL" -o "$WORK/Lime.zip"
ditto -x -k "$WORK/Lime.zip" "$WORK"

# Quit a running copy before replacing it.
pkill -x Lime 2>/dev/null && sleep 1 || true
rm -rf "$DEST/Lime.app"
ditto "$WORK/Lime.app" "$DEST/Lime.app"
xattr -dr com.apple.quarantine "$DEST/Lime.app" 2>/dev/null || true

open "$DEST/Lime.app"

echo
echo "Lime is installed in $DEST and running. Look for the lime in your menu bar."
echo "Drag a file, then tap ⇧ Shift (convert), ⌘ Command (tools) or ⌃ Control (actions)."
if ! command -v ffmpeg >/dev/null 2>&1; then
  echo
  echo "Optional, for more video and audio formats:  brew install ffmpeg webp"
fi
