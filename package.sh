#!/bin/bash

# Configuration
PROJECT_NAME="chat-storage"
SCHEME_NAME="chat-storage"
DMG_NAME="${PROJECT_NAME}.dmg"
BUILD_DIR="./build"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${PROJECT_NAME}.app"
FFMPEG_BIN="${FFMPEG_BIN:-./vendor/ffmpeg/ffmpeg}"

echo "🚀 Starting cleaning..."
xcodebuild clean -project "${PROJECT_NAME}.xcodeproj" -scheme "${SCHEME_NAME}" -configuration Release | xcpretty || true

echo "🛠 Building project..."
# Using CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO for local ad-hoc build if no certs
xcodebuild build -project "${PROJECT_NAME}.xcodeproj" \
    -scheme "${SCHEME_NAME}" \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED="NO" \
    CODE_SIGNING_ALLOWED="NO"

if [ ! -d "${APP_PATH}" ]; then
    echo "❌ Build failed. App not found at ${APP_PATH}"
    # Try looking in standard derived data if customized path failed (fallback)
    # But derivedDataPath should force it.
    exit 1
fi

echo "✅ Build successful!"
echo "📦 Preparing DMG contents..."
DMG_SOURCE_DIR="${BUILD_DIR}/dmg_source"
rm -rf "${DMG_SOURCE_DIR}"
mkdir -p "${DMG_SOURCE_DIR}"

# Copy App to source dir
cp -R "${APP_PATH}" "${DMG_SOURCE_DIR}/"

# Optional: bundle ffmpeg into app for non-technical end users.
APP_IN_DMG="${DMG_SOURCE_DIR}/${PROJECT_NAME}.app"
if [ -f "${FFMPEG_BIN}" ]; then
    echo "📎 Bundling ffmpeg from: ${FFMPEG_BIN}"
    mkdir -p "${APP_IN_DMG}/Contents/Resources"
    cp "${FFMPEG_BIN}" "${APP_IN_DMG}/Contents/Resources/ffmpeg"
    chmod +x "${APP_IN_DMG}/Contents/Resources/ffmpeg"
else
    echo "⚠️ ffmpeg binary not found at ${FFMPEG_BIN}. Skipping bundle step."
fi

# Create Applications symlink
ln -s /Applications "${DMG_SOURCE_DIR}/Applications"

echo "💿 Creating DMG..."
if [ -f "${DMG_NAME}" ]; then
    rm "${DMG_NAME}"
fi

hdiutil create -volname "${PROJECT_NAME}" -srcfolder "${DMG_SOURCE_DIR}" -ov -format UDZO "${DMG_NAME}"

echo "🎉 DMG created successfully: ${DMG_NAME}"
