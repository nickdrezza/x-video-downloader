#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$ROOT_DIR/.build/tests"
mkdir -p "$TEST_DIR"
TEST_FIXTURES="$(mktemp -d "$TEST_DIR/fixtures.XXXXXX")"
trap 'rm -rf "$TEST_FIXTURES"' EXIT
swiftc "$ROOT_DIR/Sources/XVideoDownloader/MediaCompression.swift" \
  "$ROOT_DIR/Sources/XVideoDownloader/MediaSize.swift" \
  "$ROOT_DIR/Tests/MediaCompressionTests.swift" -o "$TEST_DIR/media-tests"
"$TEST_DIR/media-tests" "$TEST_FIXTURES" "$(command -v ffmpeg)" "$(command -v ffprobe)"
