#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="X Downloader"
STAGING_DIR="$(mktemp -d /tmp/x-downloader-package.XXXXXX)"
trap 'rm -rf "$STAGING_DIR"' EXIT

"$ROOT_DIR/scripts/build.sh"
cd "$ROOT_DIR/.build"
zip -q -r -X "$APP_NAME.zip" "$APP_NAME.app"
unzip -t "$APP_NAME.zip" >/dev/null
cp -R "$APP_NAME.app" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$APP_NAME.dmg" >/dev/null
hdiutil verify "$APP_NAME.dmg" >/dev/null

echo "Packaged: $ROOT_DIR/.build/$APP_NAME.zip"
echo "Packaged: $ROOT_DIR/.build/$APP_NAME.dmg"
