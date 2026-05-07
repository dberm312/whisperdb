#!/bin/bash
set -e

APP_NAME="WhisperDB"
APP_DIR="$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "Building $APP_NAME..."
swift build -c debug

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp .build/debug/$APP_NAME "$MACOS/"
cp WhisperDB/Info.plist "$CONTENTS/"
cp -R WhisperDB/Resources/. "$RESOURCES/"

# Copy .env into Resources so the app can find it
if [ -f .env ]; then
    cp .env "$RESOURCES/"
fi

echo "Signing app bundle..."
codesign --force --sign - "$APP_DIR"

echo ""
echo "Done! Run with:"
echo "  open $APP_DIR"
echo ""
echo "First launch: grant microphone access if macOS prompts for it."
