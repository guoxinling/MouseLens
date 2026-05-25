#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CANONICAL_APP_PATH="$ROOT_DIR/.LocalTestApp/MouseLens.app"
CANONICAL_EXECUTABLE="$CANONICAL_APP_PATH/Contents/MacOS/MouseLens"

if [[ ! -d "$CANONICAL_APP_PATH" ]]; then
  echo "Canonical local test app does not exist yet." >&2
  echo "Run ./scripts/prepare_local_test_app.sh --open first." >&2
  exit 1
fi

if [[ ! -x "$CANONICAL_EXECUTABLE" ]]; then
  echo "Canonical local test app executable does not exist:" >&2
  echo "  $CANONICAL_EXECUTABLE" >&2
  echo "Run ./scripts/prepare_local_test_app.sh first." >&2
  exit 1
fi

pkill -x "MouseLens" >/dev/null 2>&1 || true
sleep 0.3

echo "Opening canonical local test app:"
echo "  $CANONICAL_APP_PATH"
nohup "$CANONICAL_EXECUTABLE" >/dev/null 2>&1 &
disown
