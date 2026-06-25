#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h}"
APP_DIR="$ROOT_DIR/MediaDownloader.app"
BIN="$APP_DIR/Contents/MacOS/MediaDownloader"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ICON_PNG="$ROOT_DIR/MediaDownloaderIcon-1024.png"
ICONSET="$ROOT_DIR/MediaDownloaderIcon.iconset"
ICON="$APP_DIR/Contents/Resources/MediaDownloaderIcon.icns"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-module-cache" \
  swift "$ROOT_DIR/scripts/generate_media_downloader_icon.swift" "$ICON_PNG"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_PNG" "$ICONSET/icon_512x512@2x.png"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-module-cache" \
  swift "$ROOT_DIR/scripts/make_icns.swift" "$ICON" \
  icp4="$ICONSET/icon_16x16.png" \
  icp5="$ICONSET/icon_32x32.png" \
  icp6="$ICONSET/icon_32x32@2x.png" \
  ic07="$ICONSET/icon_128x128.png" \
  ic08="$ICONSET/icon_256x256.png" \
  ic09="$ICONSET/icon_512x512.png" \
  ic10="$ICONSET/icon_512x512@2x.png"

CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.clang-module-cache" \
  swiftc "$ROOT_DIR/MediaDownloaderApp.swift" -o "$BIN"

rm -rf "$APP_DIR/Contents/_CodeSignature"
codesign --force --deep --options runtime --sign "$CODESIGN_IDENTITY" "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "Built $APP_DIR"
