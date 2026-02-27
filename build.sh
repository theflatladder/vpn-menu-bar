#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="VPNMenuBar"
APP_DIR="$ROOT_DIR/build/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

swiftc \
  "$ROOT_DIR/App"/*.swift \
  -framework AppKit \
  -framework ServiceManagement \
  -o "$MACOS_DIR/$APP_NAME"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"

echo "Built: $APP_DIR"
