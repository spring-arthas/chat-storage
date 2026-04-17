#!/bin/bash
set -e

APP_NAME="chat-storage"
DMG_NAME="${APP_NAME}.dmg"
APP_DIR="build/Release/${APP_NAME}.app"
STAGING_DIR="build/dmg_stage"

echo "➡️  Building $APP_NAME for Release..."
xcodebuild -project chat-storage.xcodeproj -scheme chat-storage -configuration Release build CODE_SIGNING_ALLOWED=NO -quiet

if [ ! -d "$APP_DIR" ]; then
    echo "❌ Error: App not built at $APP_DIR"
    exit 1
fi

echo "➡️  Preparing DMG staging area..."
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

echo "➡️  Copying App..."
cp -R "$APP_DIR" "$STAGING_DIR/"

echo "➡️  Creating Applications symlink..."
ln -s /Applications "$STAGING_DIR/Applications"

echo "➡️  Creating DMG ($DMG_NAME)..."
# Remove existing dmg if any
rm -f "$DMG_NAME"
hdiutil create -volname "Chat Storage" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

echo "🧹 Cleaning up..."
rm -rf "$STAGING_DIR"

echo "✅ DMG created successfully: $(pwd)/$DMG_NAME"
