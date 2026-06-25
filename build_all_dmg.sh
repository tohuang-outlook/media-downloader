#!/bin/zsh
# build_all_dmg.sh
# Builds both SubtitleBurner.app and MediaDownloader.app,
# then packages them together into a single distributable DMG.
#
# Usage:  ./build_all_dmg.sh
# Output: SubtitleBurner-Tools.dmg

set -euo pipefail

ROOT_DIR="${0:A:h}"
DMG_NAME="SubtitleBurner-Tools.dmg"
DMG_PATH="$ROOT_DIR/$DMG_NAME"
VOLUME_NAME="SubtitleBurnerTools"
STAGING="$ROOT_DIR/.dmg_staging"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
NOTARY_APPLE_ID="${NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${NOTARY_PASSWORD:-}"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-}"

notarize_if_configured() {
    local target="$1"

    if [[ -n "$NOTARY_PROFILE" ]]; then
        echo "▶ Notarizing with notarytool profile: $NOTARY_PROFILE"
        xcrun notarytool submit "$target" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$target"
        return
    fi

    if [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_PASSWORD" && -n "$NOTARY_TEAM_ID" ]]; then
        echo "▶ Notarizing with Apple ID credentials…"
        xcrun notarytool submit "$target" \
            --apple-id "$NOTARY_APPLE_ID" \
            --password "$NOTARY_PASSWORD" \
            --team-id "$NOTARY_TEAM_ID" \
            --wait
        xcrun stapler staple "$target"
        return
    fi

    echo "▶ Skipping notarization (no NOTARY_PROFILE or Apple ID credentials configured)…"
}

# ── Cleanup any leftover files from previous runs ───────────────────────────
TEMP_DMG="$ROOT_DIR/.tmp_tools.dmg"
MOUNT_DIR="$ROOT_DIR/.dmg_mount"
hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
diskutil unmount force "$MOUNT_DIR" 2>/dev/null || true
rm -f "$TEMP_DMG"
rm -rf "$MOUNT_DIR"
rm -rf "$ROOT_DIR/.dmg_staging"

# ── Step 1: Build both apps ──────────────────────────────────────────────────
echo "▶ Building SubtitleBurner.app…"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$ROOT_DIR/build.sh"
echo "✅ SubtitleBurner.app built"

echo ""
echo "▶ Building MediaDownloader.app…"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$ROOT_DIR/build_media_downloader.sh"
echo "✅ MediaDownloader.app built"

# ── Step 2: Prepare staging folder ──────────────────────────────────────────
echo ""
echo "▶ Preparing DMG contents…"
rm -rf "$STAGING"
mkdir -p "$STAGING"

cp -R "$ROOT_DIR/SubtitleBurner.app"   "$STAGING/"
cp -R "$ROOT_DIR/MediaDownloader.app"  "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# ── Step 3: Create temporary writable DMG ───────────────────────────────────
echo "▶ Creating DMG…"
TEMP_DMG="$ROOT_DIR/.tmp_tools.dmg"
rm -f "$TEMP_DMG"

APP_SIZE_KB=$(du -sk "$STAGING" | awk '{print $1}')
DMG_SIZE_KB=$(( APP_SIZE_KB + 30720 ))

hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,b=16" \
    -format UDRW \
    -size ${DMG_SIZE_KB}k \
    "$TEMP_DMG"

# ── Step 4: Mount and set window layout ─────────────────────────────────────
echo "▶ Setting DMG window layout…"
MOUNT_DIR="$ROOT_DIR/.dmg_mount"
# Force unmount if already mounted from a previous failed run
hdiutil detach "$MOUNT_DIR" -force 2>/dev/null || true
diskutil unmount force "$MOUNT_DIR" 2>/dev/null || true
sleep 1
rm -rf "$MOUNT_DIR"
mkdir -p "$MOUNT_DIR"

hdiutil attach "$TEMP_DMG" \
    -readwrite \
    -noverify \
    -noautoopen \
    -mountpoint "$MOUNT_DIR"

sleep 2
echo "▶ Skipping window layout (cosmetic only)…"

# ── Step 5: Clean up hidden files ───────────────────────────────────────────
echo "▶ Cleaning up…"
sync; sleep 1
rm -rf "$MOUNT_DIR/.fseventsd"
rm -rf "$MOUNT_DIR/.Spotlight-V100"
rm -rf "$MOUNT_DIR/.Trashes"
find "$MOUNT_DIR" -name ".DS_Store" -delete 2>/dev/null || true

# ── Step 6: Convert to compressed read-only DMG ─────────────────────────────
echo "▶ Compressing DMG…"
hdiutil detach "$MOUNT_DIR" -force
sleep 1

rm -f "$DMG_PATH"
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

# ── Step 7: Ad-hoc sign ─────────────────────────────────────────────────────
echo "▶ Signing DMG…"
codesign --force --sign "$CODESIGN_IDENTITY" "$DMG_PATH" 2>/dev/null || true

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    notarize_if_configured "$DMG_PATH"
fi

# ── Step 8: Cleanup temp files ──────────────────────────────────────────────
rm -f "$TEMP_DMG"
rm -rf "$STAGING"
rm -rf "$MOUNT_DIR"

# ── Done ────────────────────────────────────────────────────────────────────
DMG_SIZE=$(du -sh "$DMG_PATH" | awk '{print $1}')
echo ""
echo "✅ Done!"
echo "   📦 $DMG_PATH  ($DMG_SIZE)"
echo ""
echo "   To install on another Mac:"
echo "   1. Copy $DMG_NAME to the other Mac"
echo "   2. Double-click to open it"
echo "   3. Drag both apps → Applications"
echo ""
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
    echo "   ⚠️  First launch: right-click the app → Open (to bypass Gatekeeper)"
else
    if [[ -n "$NOTARY_PROFILE" || ( -n "$NOTARY_APPLE_ID" && -n "$NOTARY_PASSWORD" && -n "$NOTARY_TEAM_ID" ) ]]; then
        echo "   ✅ Signed and notarized for smoother first launch on other Macs"
    else
        echo "   ⚠️  Signed, but not notarized yet. First launch may still need right-click → Open"
    fi
fi
