#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="CodexPaceBar"
DISPLAY_NAME="Codex Pace Bar"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$DISPLAY_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cd "$ROOT_DIR"

case "$BUILD_CONFIGURATION" in
  debug|release) ;;
  *)
    echo "BUILD_CONFIGURATION must be debug or release." >&2
    exit 2
    ;;
esac

case "$MODE" in
  run|--build-only|build-only|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify) ;;
  *)
    echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2
    exit 2
    ;;
esac

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

if [[ "$MODE" != "--build-only" && "$MODE" != "build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

BUILD_CONFIGURATION="$BUILD_CONFIGURATION" bash "$ROOT_DIR/script/stage_app.sh"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --build-only|build-only)
    echo "$APP_BUNDLE"
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    test -x "$APP_BINARY"
    pgrep -x "$APP_NAME" >/dev/null
    ;;
esac
