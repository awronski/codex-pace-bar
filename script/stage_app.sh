#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexPaceBar"
DISPLAY_NAME="Codex Pace Bar"
BUNDLE_ID="app.codexpacebar.macos"
MIN_SYSTEM_VERSION="15.0"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_VERSION="$(tr -d '[:space:]' < "$ROOT_DIR/VERSION")"
APP_BUNDLE="$ROOT_DIR/dist/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
ACTIVITY_AUDIT_BINARY="$APP_RESOURCES/ActivityInsightsAudit"
ACTIVITY_COLLECTOR_BINARY="$APP_RESOURCES/ActivityInsightsCollector"
INFO_PLIST="$APP_CONTENTS/Info.plist"

case "$BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "BUILD_CONFIGURATION must be debug or release." >&2
    exit 2
    ;;
esac

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION" --product "$APP_NAME"
swift build -c "$BUILD_CONFIGURATION" --product ActivityInsightsAudit
swift build -c "$BUILD_CONFIGURATION" --product ActivityInsightsCollector
BUILD_BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BIN_DIR/$APP_NAME" "$APP_BINARY"
cp "$BUILD_BIN_DIR/ActivityInsightsAudit" "$ACTIVITY_AUDIT_BINARY"
cp "$BUILD_BIN_DIR/ActivityInsightsCollector" "$ACTIVITY_COLLECTOR_BINARY"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY" "$ACTIVITY_AUDIT_BINARY" "$ACTIVITY_COLLECTOR_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$ACTIVITY_AUDIT_BINARY"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$ACTIVITY_COLLECTOR_BINARY"
  codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$APP_BUNDLE"
else
  codesign --force --sign - --timestamp=none "$ACTIVITY_AUDIT_BINARY"
  codesign --force --sign - --timestamp=none "$ACTIVITY_COLLECTOR_BINARY"
  codesign --force --sign - --timestamp=none "$APP_BUNDLE"
fi

test -x "$APP_BINARY"
test -f "$APP_RESOURCES/AppIcon.icns"
test -x "$ACTIVITY_AUDIT_BINARY"
test -x "$ACTIVITY_COLLECTOR_BINARY"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$ACTIVITY_AUDIT_BINARY"
codesign --verify --strict --verbose=2 "$ACTIVITY_COLLECTOR_BINARY"

echo "$APP_BUNDLE"
