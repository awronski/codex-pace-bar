#!/usr/bin/env bash
set -euo pipefail

DISPLAY_NAME="Codex Pace Bar"
DMG_NAME="CodexPaceBar.dmg"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
NOTARIZE="${NOTARIZE:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APP_ZIP="$DIST_DIR/CodexPaceBar-notary.zip"

cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  if [[ -z "$SIGNING_IDENTITY" ]]; then
    echo "NOTARIZE=1 requires SIGNING_IDENTITY." >&2
    exit 1
  fi

  if [[ -z "$NOTARY_PROFILE" ]]; then
    echo "NOTARIZE=1 requires NOTARY_PROFILE." >&2
    exit 1
  fi
fi

notarize() {
  local artifact="$1"

  xcrun notarytool submit "$artifact" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
}

create_dmg() {
  rm -rf "$DMG_ROOT" "$DMG_PATH"
  mkdir -p "$DMG_ROOT"
  cp -R "$APP_BUNDLE" "$DMG_ROOT/"
  ln -s /Applications "$DMG_ROOT/Applications"

  hdiutil create \
    -volname "$DISPLAY_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
}

rm -rf "$DMG_ROOT" "$DMG_PATH" "$APP_ZIP"
BUILD_CONFIGURATION=release SIGNING_IDENTITY="$SIGNING_IDENTITY" \
  bash "$ROOT_DIR/script/stage_app.sh"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "Ad-hoc app signature verified; Developer ID release proof is not available without SIGNING_IDENTITY."
fi

if [[ "$NOTARIZE" == "1" ]]; then
  ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"
  notarize "$APP_ZIP"
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  spctl -a -vvv -t exec "$APP_BUNDLE"
  rm -f "$APP_ZIP"
fi

create_dmg

if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ "$NOTARIZE" == "1" ]]; then
  notarize "$DMG_PATH"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
fi

echo "$DMG_PATH"
