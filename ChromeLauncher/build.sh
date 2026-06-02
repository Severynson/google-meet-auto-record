#!/bin/bash
set -euo pipefail

APP_NAME="ChromeLauncher"
APP_DIR="${APP_NAME}.app"
BUNDLE_ID="com.local.chromelauncher"

echo "Building ${APP_DIR}..."

# Clean previous build
rm -rf "${APP_DIR}"

# Create bundle structure
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Write Info.plist
cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Google Chrome</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>launch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Write the launcher script
cat > "${APP_DIR}/Contents/MacOS/launch" <<'SCRIPT'
#!/bin/bash
# --remote-debugging-port=9222 lets MeetRecorder use Chrome DevTools Protocol
# to click elements by jsname (language-independent, unlike aria-label).
open -na "Google Chrome" --args --remote-debugging-port=9222
SCRIPT

chmod +x "${APP_DIR}/Contents/MacOS/launch"

echo ""
echo "Done: ${APP_DIR}"
echo ""
echo "Next steps:"
echo "  1. Copy Chrome's icon onto this app:"
echo "       - Get Info on Google Chrome (Cmd+I)"
echo "       - Click the icon in the top-left of that dialog, press Cmd+C"
echo "       - Get Info on ${APP_DIR} (Cmd+I)"
echo "       - Click the icon in the top-left of that dialog, press Cmd+V"
echo "  2. Drag ${APP_DIR} to your Dock."
echo "  3. Remove original Google Chrome from the Dock."
