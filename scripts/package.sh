#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="X Video Downloader"

"$ROOT_DIR/scripts/build.sh"
cd "$ROOT_DIR/.build"
zip -q -r -X "$APP_NAME.zip" "$APP_NAME.app"
unzip -t "$APP_NAME.zip" >/dev/null

echo "Packaged: $ROOT_DIR/.build/$APP_NAME.zip"
