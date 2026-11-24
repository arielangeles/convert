#!/usr/bin/env bash
# Builds Convert.app, installs it to ~/Applications and registers the Finder service.
#
# Usage: ./scripts/build.sh [--no-install]
#
# Optional environment (used by CI, handy locally too):
#   VERSION=1.2.0      sets CFBundleShortVersionString in the built bundle
#   BUILD_NUMBER=42    sets CFBundleVersion in the built bundle
#   UNIVERSAL=1        builds a universal binary (arm64 + x86_64); needs full Xcode
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Convert.app"
INSTALL_DIR="$HOME/Applications"

command -v swift >/dev/null || { echo "✗ swift not found. Run: xcode-select --install"; exit 1; }

SWIFT_FLAGS=(-c release)
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  SWIFT_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "→ Compiling (release)…"
swift build "${SWIFT_FLAGS[@]}"
BIN="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)/Convert"

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Convert"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"

PLIST="$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PLIST"
fi
if [[ -n "${BUILD_NUMBER:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "$PLIST"
fi
plutil -lint "$PLIST" >/dev/null

echo "→ Ad-hoc signing…"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  echo "→ Installing to ${INSTALL_DIR}…"
  mkdir -p "$INSTALL_DIR"
  pkill -x Convert 2>/dev/null || true
  rm -rf "$INSTALL_DIR/Convert.app"
  cp -R "$APP" "$INSTALL_DIR/"

  echo "→ Registering with Launch Services and refreshing Services menu…"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/Convert.app"
  /System/Library/CoreServices/pbs -update

  if ! command -v ffmpeg >/dev/null && [ ! -x /opt/homebrew/bin/ffmpeg ] && [ ! -x /usr/local/bin/ffmpeg ] && [ ! -x "$HOME/.homebrew/bin/ffmpeg" ]; then
    echo "⚠︎ ffmpeg not found. Audio/video/WebP need it: brew install ffmpeg"
  fi
  echo "✓ Done. Right-click a file in Finder › Convert… (under Quick Actions/Services)."
else
  echo "✓ Built ${APP}"
fi
