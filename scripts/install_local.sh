#!/bin/zsh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$PROJECT_ROOT/Wiki Time/Wiki Time.xcodeproj"
SCHEME="Wiki Time"
APP_NAME="Wiki Time.app"
PROCESS_NAME="Wiki Time"
INSTALL_PATH="/Applications/$APP_NAME"
DERIVED_DATA_PATH="$(mktemp -d "${TMPDIR:-/tmp}/wiki-time-build.XXXXXX")"
BUILD_APP_PATH="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

cleanup() {
  rm -rf "$DERIVED_DATA_PATH"
}

trap cleanup EXIT

echo "Using derived data at:"
echo "  $DERIVED_DATA_PATH"

echo "Building $SCHEME (Release)..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build

if [[ ! -d "$BUILD_APP_PATH" ]]; then
  echo "Build succeeded but app was not found at:"
  echo "  $BUILD_APP_PATH"
  exit 1
fi

echo "Stopping running app if needed..."
pkill -x "$PROCESS_NAME" || true

echo "Installing to /Applications..."
if [[ -d "$INSTALL_PATH" ]]; then
  "$LSREGISTER" -u "$INSTALL_PATH" || true
  rm -rf "$INSTALL_PATH"
fi

ditto "$BUILD_APP_PATH" "$INSTALL_PATH"
touch "$INSTALL_PATH"

echo "Refreshing LaunchServices and icon caches..."
"$LSREGISTER" -f -R -trusted "$INSTALL_PATH"
killall iconservicesagent 2>/dev/null || true
killall Dock 2>/dev/null || true

echo "Installed:"
echo "  $INSTALL_PATH"

if [[ "${RESET_LAUNCHPAD:-0}" == "1" ]]; then
  echo "Resetting Launchpad database..."
  rm -f "$HOME/Library/Application Support/Dock/"*.db(N)

  LAUNCHPAD_DB_DIR="$(getconf DARWIN_USER_DIR)com.apple.dock.launchpad/db"
  if [[ -d "$LAUNCHPAD_DB_DIR" ]]; then
    rm -f "$LAUNCHPAD_DB_DIR"/db(N) "$LAUNCHPAD_DB_DIR"/db-shm(N) "$LAUNCHPAD_DB_DIR"/db-wal(N)
  fi

  killall Dock 2>/dev/null || true
fi
