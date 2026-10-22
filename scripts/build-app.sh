#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
IDENTITY_FILE="$PROJECT_DIR/.local-signing/identity.sha1"
SIGNING_IDENTITY="${DESKTOP_PET_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" && -f "$IDENTITY_FILE" ]]; then
    SIGNING_IDENTITY="$(cat "$IDENTITY_FILE")"
fi
if [[ ! "$SIGNING_IDENTITY" =~ ^[A-Fa-f0-9]{40}$ ]]; then
    echo 'A fixed signing certificate is required. Existing app has not been changed.' >&2
    echo 'See docs/LOCAL_SIGNING.md; ad-hoc fallback is intentionally disabled.' >&2
    exit 1
fi
SIGNING_IDENTITY="$(printf '%s' "$SIGNING_IDENTITY" | tr '[:lower:]' '[:upper:]')"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$SIGNING_IDENTITY"; then
    echo 'Configured signing certificate is unavailable. Existing app has not been changed.' >&2
    exit 1
fi
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_DIR/.build/swift-module-cache"
BUILD_OPTIONS=(--disable-sandbox --cache-path "$PROJECT_DIR/.build/cache" --config-path "$PROJECT_DIR/.build/config" --security-path "$PROJECT_DIR/.build/security" --manifest-cache local -debug-info-format none)
swift build -c release "${BUILD_OPTIONS[@]}"
BIN_DIR="$(swift build -c release --show-bin-path "${BUILD_OPTIONS[@]}")"
APP_DIR="$PROJECT_DIR/build/DesktopPet.app"
mkdir -p "$PROJECT_DIR/build"
STAGE_DIR="$(mktemp -d "$PROJECT_DIR/build/.signed-build.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGE_APP="$STAGE_DIR/DesktopPet.app"
mkdir -p "$STAGE_APP/Contents/MacOS" "$STAGE_APP/Contents/Resources"
cp "$BIN_DIR/DesktopPet" "$STAGE_APP/Contents/MacOS/DesktopPet"
cp "$PROJECT_DIR/Info.plist" "$STAGE_APP/Contents/Info.plist"
cp "$PROJECT_DIR/docs/PRIVACY.md" "$STAGE_APP/Contents/Resources/PRIVACY.md"
SPARKLE_DIR="$PROJECT_DIR/.build/artifacts/sparkle/Sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo 'Pinned Sparkle framework is missing. Existing app has not been changed.' >&2
    exit 1
fi
mkdir -p "$STAGE_APP/Contents/Frameworks"
/usr/bin/ditto "$SPARKLE_FRAMEWORK" "$STAGE_APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$STAGE_APP/Contents/Resources/Sparkle-LICENSE.txt"
# Render from the pet's shared vector artwork, then package every macOS icon size.
ICONSET_DIR="$STAGE_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"
"$STAGE_APP/Contents/MacOS/DesktopPet" --render-app-icon "$ICONSET_DIR/icon_512x512@2x.png"
for ICON_SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$ICON_SIZE" "$ICON_SIZE" "$ICONSET_DIR/icon_512x512@2x.png" --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}.png" >/dev/null
    if [[ "$ICON_SIZE" != 512 ]]; then
        DOUBLE_SIZE=$((ICON_SIZE * 2))
        /usr/bin/sips -z "$DOUBLE_SIZE" "$DOUBLE_SIZE" "$ICONSET_DIR/icon_512x512@2x.png" --out "$ICONSET_DIR/icon_${ICON_SIZE}x${ICON_SIZE}@2x.png" >/dev/null
    fi
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$STAGE_APP/Contents/Resources/AppIcon.icns"
# A build number distinguishes updates without changing the signing identity.
CURRENT_BUILD=0
if [[ -f "$APP_DIR/Contents/Info.plist" ]]; then
    CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_DIR/Contents/Info.plist")"
fi
if [[ ! "$CURRENT_BUILD" =~ ^[0-9]{1,9}$ ]]; then
    echo 'Invalid existing build number. Existing app has not been changed.' >&2
    exit 1
fi
NEXT_BUILD="${DESKTOP_PET_BUILD_NUMBER:-$((10#$CURRENT_BUILD + 1))}"
if [[ ! "$NEXT_BUILD" =~ ^[1-9][0-9]{0,8}$ ]] || ((10#$NEXT_BUILD <= 10#$CURRENT_BUILD)); then
    echo 'Build number must be a new positive integer. Existing app has not been changed.' >&2
    exit 1
fi
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$STAGE_APP/Contents/Info.plist"
REQUIREMENT="designated => identifier \"local.desktop-pet.prototype\" and certificate leaf = H\"$SIGNING_IDENTITY\""
codesign --force --sign "$SIGNING_IDENTITY" --timestamp=none --requirements "=$REQUIREMENT" "$STAGE_APP"
codesign --verify --deep --strict "$STAGE_APP"
codesign --verify -R "=identifier \"local.desktop-pet.prototype\" and certificate leaf = H\"$SIGNING_IDENTITY\"" "$STAGE_APP"
# Keep the last build recoverable, and never overwrite it before signing succeeds.
if [[ -e "$APP_DIR" ]]; then
    BACKUP_DIR="$(mktemp -d "$PROJECT_DIR/build/previous-build.XXXXXX")"
    mv "$APP_DIR" "$BACKUP_DIR/DesktopPet.app"
    if ! mv "$STAGE_APP" "$APP_DIR"; then
        mv "$BACKUP_DIR/DesktopPet.app" "$APP_DIR"
        exit 1
    fi
else
    mv "$STAGE_APP" "$APP_DIR"
fi
printf '\nBuilt: %s\nRun: open "%s"\n' "$APP_DIR" "$APP_DIR"
if [[ -n "${BACKUP_DIR:-}" ]]; then
    printf 'Previous build: %s\n' "$BACKUP_DIR/DesktopPet.app"
fi
