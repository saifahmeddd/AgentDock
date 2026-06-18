#!/usr/bin/env bash
# package-app.sh — builds AgentDock and packages it as a signed .app bundle.
#
# Usage:
#   ./scripts/package-app.sh              # ad-hoc signed (works on this Mac only)
#   ./scripts/package-app.sh "Developer ID Application: Your Name (TEAMID)"
#
# For real distribution you need a paid Apple Developer account. Ad-hoc signing
# (no argument) is fine for local use and testing. Notarization requires a
# Developer ID certificate — see docs/signing.md for that path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="AgentDock"
BUNDLE_ID="com.agentdock.AgentDock"
VERSION="0.2.0"
BUILD_NUMBER="1"
BUILD_CONFIG="${BUILD_CONFIG:-release}"
ARCH="$(uname -m)"
BUILD_DIR=".build/${ARCH}-apple-macosx/${BUILD_CONFIG}"
OUTPUT_DIR="${REPO_ROOT}/build"
BUNDLE_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
SIGN_IDENTITY="${1:--}"   # default: ad-hoc (-), pass a Developer ID as $1

echo "==> Building AgentDock (${BUILD_CONFIG}, ${ARCH})…"
swift build -c "$BUILD_CONFIG" 2>&1 | tail -5

echo "==> Assembling .app bundle…"
rm -rf "$BUNDLE_PATH"
mkdir -p "${BUNDLE_PATH}/Contents/MacOS"
mkdir -p "${BUNDLE_PATH}/Contents/Resources"

# Binary
cp "${BUILD_DIR}/${APP_NAME}" "${BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${BUNDLE_PATH}/Contents/MacOS/${APP_NAME}"

# Icon (from SwiftPM Resources)
ICNS_SRC="${REPO_ROOT}/Sources/${APP_NAME}/Resources/${APP_NAME}.icns"
if [[ -f "$ICNS_SRC" ]]; then
    cp "$ICNS_SRC" "${BUNDLE_PATH}/Contents/Resources/${APP_NAME}.icns"
fi

# Info.plist
cat > "${BUNDLE_PATH}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleSignature</key>
    <string>ADKC</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Hides the app from the Dock — menu bar only -->
    <key>LSUIElement</key>
    <true/>
    <!-- Privacy descriptions for System Frameworks -->
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>AgentDock creates calendar events for your approved work actions.</string>
    <key>NSCalendarsWriteOnlyAccessUsageDescription</key>
    <string>AgentDock creates calendar events for your approved work actions.</string>
    <key>NSUserNotificationAlertStyle</key>
    <string>alert</string>
</dict>
</plist>
PLIST

# Entitlements
ENTITLEMENTS_FILE="${REPO_ROOT}/build/AgentDock.entitlements"
cat > "$ENTITLEMENTS_FILE" << ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Required for OpenRouter API calls and URL metadata fetching -->
    <key>com.apple.security.network.client</key>
    <true/>
    <!-- Required for drag-and-drop file ingestion -->
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
    <!-- Keychain access -->
    <key>keychain-access-groups</key>
    <array>
        <string>\$(AppIdentifierPrefix)${BUNDLE_ID}</string>
    </array>
</dict>
</plist>
ENT

echo "==> Code-signing (identity: '${SIGN_IDENTITY}')…"
codesign \
    --force \
    --deep \
    --sign "${SIGN_IDENTITY}" \
    --entitlements "${ENTITLEMENTS_FILE}" \
    --options runtime \
    "${BUNDLE_PATH}"

echo "==> Verifying signature…"
codesign --verify --deep --strict "${BUNDLE_PATH}" && echo "    Signature OK"

echo ""
echo "Build complete: ${BUNDLE_PATH}"
echo ""

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
    echo "NOTE: This is an ad-hoc signed build. It will only run on this Mac."
    echo "      Gatekeeper will block it on other machines unless you:"
    echo "        1. Obtain a paid Apple Developer account (\$99/year)"
    echo "        2. Re-run: ./scripts/package-app.sh 'Developer ID Application: Name (TEAMID)'"
    echo "        3. Notarize with: xcrun notarytool submit build/AgentDock.app --wait"
    echo ""
fi

echo "To launch:"
echo "  open \"${BUNDLE_PATH}\""
