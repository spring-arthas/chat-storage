#!/bin/bash

set -euo pipefail

PROJECT_NAME="chat-storage"
SCHEME_NAME="chat-storage"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
EXPORT_APP_DIR="$BUILD_DIR/export"
DMG_SOURCE_DIR="$BUILD_DIR/dmg_source"
DMG_PATH="$ROOT_DIR/$PROJECT_NAME.dmg"

DEVELOPER_TEAM_ID="${DEVELOPER_TEAM_ID:-}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"

if [[ -z "$DEVELOPER_TEAM_ID" ]]; then
    echo "❌ Missing DEVELOPER_TEAM_ID"
    exit 1
fi

if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
    echo "❌ Missing DEVELOPER_ID_APPLICATION"
    exit 1
fi

if [[ "$SKIP_NOTARIZATION" != "1" && -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
    echo "❌ Missing NOTARY_KEYCHAIN_PROFILE"
    echo "   Set SKIP_NOTARIZATION=1 only if you intentionally want a signed-but-not-notarized build."
    exit 1
fi

echo "🧹 Cleaning release output..."
rm -rf "$BUILD_DIR"
mkdir -p "$EXPORT_APP_DIR" "$DMG_SOURCE_DIR"
rm -f "$DMG_PATH"

echo "🔍 Checking signing identity..."
security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null || {
    echo "❌ Developer ID identity not found in keychain: $DEVELOPER_ID_APPLICATION"
    exit 1
}

echo "📦 Archiving signed release app..."
xcodebuild archive \
    -project "$ROOT_DIR/chat-storage.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$DEVELOPER_TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION"

APP_PATH="$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Signed app not found at $APP_PATH"
    exit 1
fi

echo "✅ Verifying app signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "📁 Preparing DMG contents..."
cp -R "$APP_PATH" "$EXPORT_APP_DIR/"
cp -R "$APP_PATH" "$DMG_SOURCE_DIR/"
ln -s /Applications "$DMG_SOURCE_DIR/Applications"

echo "💿 Creating DMG..."
hdiutil create \
    -volname "$PROJECT_NAME" \
    -srcfolder "$DMG_SOURCE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "✍️ Signing DMG..."
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"

if [[ "$SKIP_NOTARIZATION" == "1" ]]; then
    echo "⚠️ Skipping notarization because SKIP_NOTARIZATION=1"
    echo "✅ Signed DMG created at $DMG_PATH"
    exit 0
fi

echo "☁️ Submitting DMG for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
    --wait

echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "🔐 Final Gatekeeper check..."
spctl -a -vv -t open "$DMG_PATH"

echo "🎉 Notarized DMG created at $DMG_PATH"
