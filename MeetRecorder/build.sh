#!/bin/bash
set -euo pipefail

APP="MeetRecorder.app"
SOURCES=$(ls Sources/*.swift)
MIN_MACOS="11.0"

echo "Compiling arm64..."
swiftc $SOURCES -framework Cocoa \
    -target arm64-apple-macosx${MIN_MACOS} \
    -o MeetRecorder_arm64

echo "Compiling x86_64..."
swiftc $SOURCES -framework Cocoa \
    -target x86_64-apple-macosx${MIN_MACOS} \
    -o MeetRecorder_x86_64

echo "Creating universal binary..."
lipo -create MeetRecorder_arm64 MeetRecorder_x86_64 -output MeetRecorder
rm MeetRecorder_arm64 MeetRecorder_x86_64

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

mv MeetRecorder "$APP/Contents/MacOS/MeetRecorder"
cp Info.plist "$APP/Contents/Info.plist"

echo "Architecture: $(lipo -archs "$APP/Contents/MacOS/MeetRecorder")"
echo "Done: $(pwd)/$APP"
echo "Run with: open $APP"
echo "Package for distribution: bash package-dmg.sh"
