#!/bin/bash
set -euo pipefail

OUT="MeetRecorder"
SOURCES="Sources/main.swift Sources/Logger.swift Sources/CDPClient.swift Sources/MeetController.swift"

echo "Compiling ${OUT}..."

swiftc $SOURCES \
    -framework Cocoa \
    -o "${OUT}"

echo "Built: $(pwd)/${OUT}"
echo ""
echo "Run with: ./${OUT}"
echo "  Chrome must be launched via ChromeLauncher (needs --remote-debugging-port=9222)."
