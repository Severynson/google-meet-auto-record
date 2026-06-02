#!/bin/bash
set -euo pipefail

APP="MeetRecorder.app"
DMG="MeetRecorder.dmg"
STAGING="$(mktemp -d)/dmg_staging"

if [ ! -d "$APP" ]; then
    echo "Error: $APP not found. Run build.sh first."
    exit 1
fi

echo "Staging..."
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating $DMG..."
hdiutil create \
    -volname "MeetRecorder" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

rm -rf "$STAGING"
echo "Done: $(pwd)/$DMG"
