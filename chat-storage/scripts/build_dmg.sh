#!/bin/bash

# Configuration
PROJECT_NAME="chat-storage"
SCHEME_NAME="chat-storage"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/Export"
DMG_SOURCE="$BUILD_DIR/dmg_source"
DMG_NAME="$PROJECT_NAME.dmg"
EXPORT_OPTIONS="exportOptions.plist"

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "🧹 Cleaning Project..."
xcodebuild clean -project "../$PROJECT_NAME.xcodeproj" -scheme "$SCHEME_NAME" -configuration Release

if [ $? -ne 0 ]; then
    echo "⚠️ Clean failed (continuing...)"
fi

echo "🚀 Starting Build..."

# 1. Archive
xcodebuild archive \
    -project "../$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo "❌ Archive failed"
    exit 1
fi

echo "✅ Archive successful"

# 2. Export (Manually copy .app since exportArchive requires signing)
# For ad-hoc without signing, we can just copy the .app from the archive
echo "📦 Exporting App..."
APP_PATH="$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"
mkdir -p "$EXPORT_PATH"
cp -R "$APP_PATH" "$EXPORT_PATH/"

if [ $? -ne 0 ]; then
    echo "❌ Export failed"
    exit 1
fi

echo "✅ Export successful"

# 3. Create DMG Structure
echo "💿 Creating DMG..."
rm -rf "$DMG_SOURCE"
mkdir -p "$DMG_SOURCE"
cp -R "$EXPORT_PATH/$PROJECT_NAME.app" "$DMG_SOURCE/"
ln -s /Applications "$DMG_SOURCE/Applications"

# 4. Generate DMG
rm -f "$DMG_NAME"
hdiutil create -volname "$PROJECT_NAME Installer" -srcfolder "$DMG_SOURCE" -ov -format UDZO "$DMG_NAME"

if [ $? -ne 0 ]; then
    echo "❌ DMG creation failed"
    exit 1
fi

echo "🎉 DMG created successfully: $DMG_NAME"
