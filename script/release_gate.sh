#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

swift test
swift build -c release
bash script/check_activity_insights_isolation.sh
SIGNING_IDENTITY="" NOTARIZE=0 bash script/package_dmg.sh

DMG_PATH="$ROOT_DIR/dist/CodexPaceBar.dmg"
MOUNT_DIR="$(mktemp -d)"
cleanup() {
  hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || true
  rm -rf "$MOUNT_DIR"
}
trap cleanup EXIT

hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
APP_BUNDLE="$MOUNT_DIR/Codex Pace Bar.app"
APP_RESOURCES="$APP_BUNDLE/Contents/Resources"
test -x "$APP_BUNDLE/Contents/MacOS/CodexPaceBar"
test -x "$APP_RESOURCES/ActivityInsightsAudit"
test -x "$APP_RESOURCES/ActivityInsightsCollector"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --strict --verbose=2 "$APP_RESOURCES/ActivityInsightsAudit"
codesign --verify --strict --verbose=2 "$APP_RESOURCES/ActivityInsightsCollector"
"$APP_RESOURCES/ActivityInsightsAudit" >/dev/null

hdiutil detach "$MOUNT_DIR" -quiet
trap - EXIT
rm -rf "$MOUNT_DIR"

echo "release_gate PASS"
