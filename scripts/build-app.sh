#!/usr/bin/env bash
# Build WhisperDB and drop the fresh binary into WhisperDB.app so that
# `open WhisperDB.app` always launches the latest build.
#
# Usage:
#   ./scripts/build-app.sh           # debug build (default)
#   ./scripts/build-app.sh release   # release build
#   ./scripts/build-app.sh --run     # build (debug) then relaunch the app
#   ./scripts/build-app.sh release --run
set -euo pipefail

# Repo root = parent of this script's directory, regardless of where it's run from.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="debug"
RUN=0
for arg in "$@"; do
  case "$arg" in
    release) CONFIG="release" ;;
    debug)   CONFIG="debug" ;;
    --run)   RUN=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 1 ;;
  esac
done

APP="WhisperDB.app"
DEST="${APP}/Contents/MacOS/WhisperDB"

echo ">> swift build (${CONFIG})..."
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/WhisperDB"
[ -f "$BIN" ] || { echo "build output not found: $BIN" >&2; exit 1; }

echo ">> copying binary into ${APP}..."
cp "$BIN" "$DEST"

echo ">> re-signing (ad-hoc)..."
codesign --force --deep --sign - "$APP"

echo "OK: ${APP} updated (${CONFIG}) at $(date '+%H:%M:%S')"

if [ "$RUN" -eq 1 ]; then
  echo ">> relaunching..."
  osascript -e 'tell application "WhisperDB" to quit' 2>/dev/null || true
  pkill -f "${APP}/Contents/MacOS/WhisperDB" 2>/dev/null || true
  sleep 1
  open "$APP"
fi
