#!/usr/bin/env bash
# Bouwt MediKas.app in ./build
#   ./build.sh          → bouw de app
#   ./build.sh run      → bouw en start
#   ./build.sh install  → bouw en zet in /Applications
#   ./package.sh        → dmg + zip om te delen (zie README → Releases)
set -euo pipefail
cd "$(dirname "$0")"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/module-cache}"

# UNIVERSAL=1 → Apple silicon + Intel in één app (gebruikt door package.sh).
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} 2>&1 | grep -v "x86_64 architecture is deprecated" || true
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/MediKas"
[[ -x "$BIN" ]] || { echo "Bouwen mislukt"; exit 1; }

APP="build/MediKas.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/MediKas"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Support/AppIconDark.png "$APP/Contents/Resources/AppIconDark.png"   # Dock-icoon bij iconenstijl Donker

# Sparkle (updates). ditto houdt de symlinks van het framework intact.
SPARKLE="$(find .build/artifacts -path "*Sparkle.xcframework/macos-*/Sparkle.framework" -maxdepth 6 | head -1)"
[[ -d "$SPARKLE" ]] || { echo "Sparkle.framework niet gevonden — draai: swift package resolve"; exit 1; }
ditto "$SPARKLE" "$APP/Contents/Frameworks/Sparkle.framework"

# Ondertekenen met een vaste identiteit (Support/setup-signing.sh), anders ad-hoc.
IDENTITY="MediKas Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then SIGN="$IDENTITY"; else SIGN="-"; fi
SF="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for item in "$SF/XPCServices/Installer.xpc" "$SF/XPCServices/Downloader.xpc" "$SF/Autoupdate" "$SF/Updater.app" \
            "$APP/Contents/Frameworks/Sparkle.framework"; do
  [[ -e "$item" ]] && codesign --force --preserve-metadata=entitlements --sign "$SIGN" "$item" >/dev/null
done
codesign --force --sign "$SIGN" "$APP" >/dev/null
echo "Klaar: $APP"

case "${1:-}" in
  run)     pkill -x MediKas 2>/dev/null || true; open "$APP" ;;
  install) pkill -x MediKas 2>/dev/null || true; rm -rf /Applications/MediKas.app; cp -R "$APP" /Applications/; open /Applications/MediKas.app ;;
esac
