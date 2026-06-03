#!/bin/bash
set -euo pipefail

APP="MeetRecorder.app"
SOURCES=$(ls Sources/*.swift)
MIN_MACOS="11.0"
ICON_SOURCE="Sources/assets/icons/google-meet-rec-icon.png"

make_icon_png() {
    local pixels="$1"
    local output="$2"

    sips -s format png -Z "$pixels" "$ICON_SOURCE" --out "$output" >/dev/null
    sips --padToHeightWidth "$pixels" "$pixels" "$output" --out "$output" >/dev/null
}

build_icon() {
    if [ ! -f "$ICON_SOURCE" ]; then
        echo "Error: icon source not found: $ICON_SOURCE"
        exit 1
    fi

    local workdir
    workdir="$(mktemp -d)"
    local iconset="$workdir/AppIcon.iconset"
    mkdir -p "$iconset"

    make_icon_png 16 "$iconset/icon_16x16.png"
    make_icon_png 32 "$iconset/icon_16x16@2x.png"
    make_icon_png 32 "$iconset/icon_32x32.png"
    make_icon_png 64 "$iconset/icon_32x32@2x.png"
    make_icon_png 128 "$iconset/icon_128x128.png"
    make_icon_png 256 "$iconset/icon_128x128@2x.png"
    make_icon_png 256 "$iconset/icon_256x256.png"
    make_icon_png 512 "$iconset/icon_256x256@2x.png"
    make_icon_png 512 "$iconset/icon_512x512.png"
    make_icon_png 1024 "$iconset/icon_512x512@2x.png"

    iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$workdir"
}

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
cp buttons.json "$APP/Contents/Resources/buttons.json"
build_icon

# Code signing.
# Accessibility (TCC) permission is keyed to the app's code identity. The
# signing identifier MUST match CFBundleIdentifier (com.local.meetrecorder),
# otherwise the running process can't be matched to the grant and
# AXIsProcessTrusted() stays false even after the user grants access.
#
# A stable signing identity (self-signed is fine) gives a designated
# requirement based on the certificate, so the accessibility grant survives
# rebuilds. Ad-hoc signing changes the cdhash every build and forces the user
# to re-grant each time.
echo "Signing $APP..."
SIGN_IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/"/{print $2; exit}')}"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "  identity: $SIGN_IDENTITY"
else
    echo "  identity: ad-hoc (no codesigning identity found — grant will not survive rebuilds)"
    SIGN_IDENTITY="-"
fi

codesign --force --deep \
    --identifier "com.local.meetrecorder" \
    --sign "$SIGN_IDENTITY" \
    "$APP"

codesign --verify --verbose "$APP" 2>&1 | sed 's/^/  /'

echo "Architecture: $(lipo -archs "$APP/Contents/MacOS/MeetRecorder")"
echo "Icon: $APP/Contents/Resources/AppIcon.icns"
echo "Done: $(pwd)/$APP"
echo "Run with: open $APP"
echo "Package for distribution: bash package-dmg.sh"
