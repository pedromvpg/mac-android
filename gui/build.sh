#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GUI_DIR="${ROOT}/gui"
DIST_APP="${ROOT}/mac-android.app"

cd "$GUI_DIR"

echo "Building mac-android GUI..."
xcodebuild \
  -project MacAndroid.xcodeproj \
  -scheme mac-android \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  -quiet

APP="$(find build/Build/Products/Release -name 'mac-android.app' -maxdepth 1 | head -1)"

if [[ ! -d "$APP" ]]; then
  echo "error: build failed — app bundle not found" >&2
  exit 1
fi

echo "Installing to project root..."
rm -rf "$DIST_APP"
cp -R "$APP" "$DIST_APP"

echo
echo "Ready: $DIST_APP"
echo "Double-click mac-android.app in Finder to launch."
