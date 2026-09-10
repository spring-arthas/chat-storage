#!/bin/bash

set -euo pipefail

PROJECT_NAME="chat-storage"
SCHEME_NAME="chat-storage"
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="$ROOT_DIR/build/release"
ARCHIVE_PATH="$BUILD_DIR/$PROJECT_NAME.xcarchive"
DMG_SOURCE_DIR="$BUILD_DIR/dmg_source"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Downloads}"
BUILD_STAMP="$(date +%Y%m%d-%H%M%S)"
DMG_PATH="${DMG_PATH:-$OUTPUT_DIR/$PROJECT_NAME-universal-$BUILD_STAMP.dmg}"

# developer-id：正式分发，必须 Developer ID 签名并完成 Apple 公证。
# self-use：两台自用 Mac 临时分发，通用架构但首次启动需要右键“打开”。
DISTRIBUTION_MODE="${DISTRIBUTION_MODE:-developer-id}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"
ENTITLEMENTS_PATH="$ROOT_DIR/chat-storage/chat_storage.entitlements"

case "$DISTRIBUTION_MODE" in
    developer-id)
        if [[ -z "$DEVELOPER_ID_APPLICATION" ]]; then
            echo "Missing DEVELOPER_ID_APPLICATION"
            echo "正式分发必须使用 Developer ID Application 证书。"
            exit 1
        fi
        if [[ "$SKIP_NOTARIZATION" != "1" && -z "$NOTARY_KEYCHAIN_PROFILE" ]]; then
            echo "Missing NOTARY_KEYCHAIN_PROFILE"
            echo "正式分发必须配置 Apple 公证凭据。"
            exit 1
        fi
        security find-identity -v -p codesigning | grep -F "$DEVELOPER_ID_APPLICATION" >/dev/null || {
            echo "Developer ID identity not found: $DEVELOPER_ID_APPLICATION"
            exit 1
        }
        ;;
    self-use)
        echo "Self-use mode: universal ad-hoc DMG; Gatekeeper may require right-click Open once."
        ;;
    *)
        echo "Unsupported DISTRIBUTION_MODE: $DISTRIBUTION_MODE"
        echo "Allowed values: developer-id, self-use"
        exit 1
        ;;
esac

echo "Cleaning release output..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DMG_SOURCE_DIR" "$OUTPUT_DIR"

echo "Building universal Release archive (arm64 + x86_64)..."
xcodebuild archive \
    -project "$ROOT_DIR/chat-storage.xcodeproj" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    CODE_SIGNING_ALLOWED=NO

APP_PATH="$ARCHIVE_PATH/Products/Applications/$PROJECT_NAME.app"
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/$PROJECT_NAME"
if [[ ! -d "$APP_PATH" || ! -f "$APP_EXECUTABLE" ]]; then
    echo "Release app not found: $APP_PATH"
    exit 1
fi

if [[ "$DISTRIBUTION_MODE" == "developer-id" ]]; then
    echo "Signing app with Developer ID..."
    codesign \
        --force \
        --deep \
        --options runtime \
        --timestamp \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign "$DEVELOPER_ID_APPLICATION" \
        "$APP_PATH"
else
    echo "Applying ad-hoc signature for self-use distribution..."
    codesign \
        --force \
        --deep \
        --options runtime \
        --entitlements "$ENTITLEMENTS_PATH" \
        --sign - \
        "$APP_PATH"
fi

echo "Verifying app signature and architectures..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
APP_ARCHS="$(lipo -archs "$APP_EXECUTABLE")"
if [[ "$APP_ARCHS" != *"arm64"* || "$APP_ARCHS" != *"x86_64"* ]]; then
    echo "Universal architecture verification failed: $APP_ARCHS"
    exit 1
fi
echo "Architectures: $APP_ARCHS"

echo "Preparing DMG contents..."
cp -R "$APP_PATH" "$DMG_SOURCE_DIR/"
ln -s /Applications "$DMG_SOURCE_DIR/Applications"

echo "Creating DMG: $DMG_PATH"
hdiutil create \
    -volname "Chat Storage" \
    -srcfolder "$DMG_SOURCE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

if [[ "$DISTRIBUTION_MODE" == "developer-id" ]]; then
    echo "Signing DMG with Developer ID..."
    codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"

    if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
        echo "Submitting DMG for Apple notarization..."
        xcrun notarytool submit "$DMG_PATH" \
            --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" \
            --wait

        echo "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH"
        spctl -a -vv -t open "$DMG_PATH"
    else
        echo "Notarization skipped explicitly; this build is not ready for unrestricted distribution."
    fi
else
    codesign --force --sign - "$DMG_PATH"
fi

echo "Verifying DMG integrity..."
hdiutil verify "$DMG_PATH"
shasum -a 256 "$DMG_PATH"

echo "DMG created: $DMG_PATH"
