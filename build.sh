#!/bin/bash
# Builds build/Folder Size.app as a universal app (Intel from macOS 10.13, Apple Silicon from macOS 11).
# Needs only the Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Folder Size.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Apple Silicon Macs started with macOS 11, so the arm64 half has that as its minimum automatically.
# -Wunguarded-availability makes any API newer than 10.13 without an @available check a build error.
clang -fobjc-arc -O2 -Wall -Wunguarded-availability -Werror \
    -arch x86_64 -arch arm64 -mmacosx-version-min=10.13 \
    -framework Cocoa \
    Sources/*.m \
    -o "$APP/Contents/MacOS/FolderSize"

cp Resources/Info.plist "$APP/Contents/"

clang -fobjc-arc -framework Cocoa Tools/make_icon.m -o build/make_icon
build/make_icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature: required to run on Apple Silicon, but not a Developer ID (see README).
codesign --force --sign - "$APP"

echo "Built $APP"
