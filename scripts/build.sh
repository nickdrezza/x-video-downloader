#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APP_NAME="X Downloader"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICONSET_DIR"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ROOT_DIR/Resources/AppIcon.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$ROOT_DIR/Resources/AppIcon.png" \
    --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
SWIFT_SOURCES=("$ROOT_DIR"/Sources/XVideoDownloader/*.swift)
swiftc -O -framework AppKit \
  "${SWIFT_SOURCES[@]}" \
  -o "$APP_DIR/Contents/MacOS/XVideoDownloader"

xattr -cr "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "Built: $APP_DIR"
