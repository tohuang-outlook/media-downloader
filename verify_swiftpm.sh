#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
BUILD_PATH="/private/tmp/media-downloader-swiftpm-build"

rm -rf "$BUILD_PATH"

echo "Using SwiftPM build path: $BUILD_PATH"
swift build --build-path "$BUILD_PATH"
swift test --build-path "$BUILD_PATH"

echo "SwiftPM build and tests passed."
