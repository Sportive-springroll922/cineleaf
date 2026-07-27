#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "DMG creation requires macOS." >&2
  exit 1
fi
[[ $# -eq 2 ]] || { echo "Usage: $0 /path/to/Cineleaf.app /path/to/Cineleaf.dmg" >&2; exit 1; }

APP_PATH="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
OUTPUT_PATH="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
[[ -d "$APP_PATH" ]] || { echo "Application not found: $APP_PATH" >&2; exit 1; }

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/cineleaf-dmg.XXXXXX")"
cleanup() { rm -rf "$STAGING"; }
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING/Cineleaf.app"
ln -s /Applications "$STAGING/Applications"
printf '%s\n' 'Drag Cineleaf.app to the Applications folder. This build is ad-hoc signed and not Apple-notarized.' > "$STAGING/Drag Cineleaf to Applications.txt"
rm -f "$OUTPUT_PATH"
hdiutil create \
  -volname "Cineleaf 0.1.0" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$OUTPUT_PATH"

echo "Created non-notarized DMG: $OUTPUT_PATH"
