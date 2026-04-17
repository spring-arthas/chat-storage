#!/bin/bash
set -e

APP_NAME="chat-storage"
DMG_NAME="${APP_NAME}.dmg"
APP_DIR="build_data/Build/Products/Release/${APP_NAME}.app"
STAGING_DIR="dmg_stage"
FFMPEG_BIN="${FFMPEG_BIN:-./vendor/ffmpeg/ffmpeg}"

echo "======================================"
echo "➡️  Building $APP_NAME for Release..."
echo "======================================"
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Release build CODE_SIGNING_ALLOWED=NO -derivedDataPath ./build_data

if [ ! -d "$APP_DIR" ]; then
    echo "❌ Error: App not built at $APP_DIR"
    exit 1
fi

echo "======================================"
echo "➡️  Preparing DMG staging area..."
echo "======================================"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "➡️  Copying App..."
cp -R "$APP_DIR" "$STAGING_DIR/"

APP_IN_STAGE="${STAGING_DIR}/${APP_NAME}.app"
if [ -f "$FFMPEG_BIN" ]; then
    echo "➡️  Bundling ffmpeg from $FFMPEG_BIN ..."
    mkdir -p "${APP_IN_STAGE}/Contents/Resources"
    cp "$FFMPEG_BIN" "${APP_IN_STAGE}/Contents/Resources/ffmpeg"
    chmod +x "${APP_IN_STAGE}/Contents/Resources/ffmpeg"
else
    echo "⚠️  ffmpeg binary not found at $FFMPEG_BIN, skipping bundle."
fi

echo "➡️  Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

echo "======================================"
echo "➡️  Creating DMG ($DMG_NAME)..."
echo "======================================"
rm -f "$DMG_NAME"
hdiutil create -volname "Chat Storage Installer" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

echo "🧹 Cleaning up..."
rm -rf "$STAGING_DIR"

echo "✅ DMG created successfully at: $(pwd)/$DMG_NAME"
