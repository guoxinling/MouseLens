#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedDataLocalTest"
LOCAL_TEST_DIR="$ROOT_DIR/.LocalTestApp"
APP_NAME="MouseLens.app"
BUILT_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
CANONICAL_APP_PATH="$LOCAL_TEST_DIR/$APP_NAME"
CANONICAL_EXECUTABLE="$CANONICAL_APP_PATH/Contents/MacOS/MouseLens"
BUNDLE_IDENTIFIER="com.guoxl.MouseLens"

RESET_PERMISSIONS=0
OPEN_APP=0
CLEAN_OUTPUT=0

usage() {
  cat <<'EOF'
Usage: ./scripts/prepare_local_test_app.sh [options]

Options:
  --reset-permissions   Reset Screen Recording, Microphone, and Accessibility for MouseLens
  --open                Open the canonical local test app after building
  --clean               Remove the previous local test build before rebuilding
  --help                Show this message

This script builds MouseLens into one canonical local-testing path:
  .LocalTestApp/MouseLens.app
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset-permissions)
      RESET_PERMISSIONS=1
      shift
      ;;
    --open)
      OPEN_APP=1
      shift
      ;;
    --clean)
      CLEAN_OUTPUT=1
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

echo "Preparing canonical local test build for MouseLens..."

if pgrep -x "MouseLens" >/dev/null 2>&1; then
  echo "Closing running MouseLens instances..."
  pkill -x "MouseLens" || true
  sleep 1
fi

if [[ "$CLEAN_OUTPUT" -eq 1 ]]; then
  echo "Removing previous local test artifacts..."
  rm -rf "$DERIVED_DATA_PATH" "$LOCAL_TEST_DIR"
fi

mkdir -p "$LOCAL_TEST_DIR"

echo "Building Release app into fixed DerivedData path..."
xcodebuild \
  -project "$ROOT_DIR/MouseLens.xcodeproj" \
  -scheme MouseLens \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$BUILT_APP_PATH" ]]; then
  echo "Expected built app was not found at:" >&2
  echo "  $BUILT_APP_PATH" >&2
  exit 1
fi

echo "Copying app into canonical local test path..."
rm -rf "$CANONICAL_APP_PATH"
ditto "$BUILT_APP_PATH" "$CANONICAL_APP_PATH"

echo "Re-signing canonical app with stable local designated requirement..."
/usr/bin/codesign --force --deep --sign - --requirements '=designated => identifier "com.guoxl.MouseLens"' "$CANONICAL_APP_PATH"

if [[ "$RESET_PERMISSIONS" -eq 1 ]]; then
  echo "Resetting local macOS permissions for $BUNDLE_IDENTIFIER..."
  tccutil reset ScreenCapture "$BUNDLE_IDENTIFIER" || true
  tccutil reset Accessibility "$BUNDLE_IDENTIFIER" || true
  tccutil reset Microphone "$BUNDLE_IDENTIFIER" || true
fi

echo
echo "Canonical local test app is ready:"
echo "  $CANONICAL_APP_PATH"
echo
echo "Designated requirement:"
/usr/bin/codesign -d -r- "$CANONICAL_APP_PATH" 2>&1 | sed 's/^/  /'
echo
echo "From now on, only test this app:"
echo "  $CANONICAL_APP_PATH"

if [[ "$OPEN_APP" -eq 1 ]]; then
  echo
  echo "Opening canonical local test app..."
  pkill -x "MouseLens" >/dev/null 2>&1 || true
  sleep 0.3
  if [[ -x "$CANONICAL_EXECUTABLE" ]]; then
    nohup "$CANONICAL_EXECUTABLE" >/dev/null 2>&1 &
    disown
  else
    echo "Canonical executable does not exist:" >&2
    echo "  $CANONICAL_EXECUTABLE" >&2
    exit 1
  fi
fi
