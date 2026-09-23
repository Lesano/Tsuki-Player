#!/usr/bin/env bash
# Builds the release APK and copies it + a changelog to ~/Downloads.
# Usage: scripts/build_release.sh [--changelog <file>]
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}' | tr -d '"')
VERSION_NAME="${VERSION%%+*}"
CHANGELOG="${1:-}"

flutter build apk --release

APK="build/app/outputs/flutter-apk/app-release.apk"
DEST="/home/leandro/Downloads/tsuki-player-v${VERSION_NAME}.apk"

cp "$APK" "$DEST"
echo "APK -> $DEST"

if [[ -n "$CHANGELOG" && -f "$CHANGELOG" ]]; then
  CHG_DEST="/home/leandro/Downloads/tsuki-player-v${VERSION_NAME}-changelog.md"
  cp "$CHANGELOG" "$CHG_DEST"
  echo "Changelog -> $CHG_DEST"
fi