#!/usr/bin/env bash
# Builds Convert.app, installs it to ~/Applications and registers the Finder service.
# Usage: ./scripts/build.sh [--no-install]
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP="$ROOT/build/Convert.app"
INSTALL_DIR="$HOME/Applications"

command -v swift >/dev/null || { echo "✗ swift not found. Run: xcode-select --install"; exit 1; }

echo "→ Compiling (release)…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Convert"

echo "→ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Convert"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
plutil -lint "$APP/Contents/Info.plist" >/dev/null

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
fi

if ! command -v ffmpeg >/dev/null && [ ! -x /opt/homebrew/bin/ffmpeg ] && [ ! -x /usr/local/bin/ffmpeg ] && [ ! -x "$HOME/.homebrew/bin/ffmpeg" ]; then
  echo "⚠︎ ffmpeg not found. Audio/video/WebP need it: brew install ffmpeg"
fi

echo "✓ Done. Right-click a file in Finder › Convert… (under Quick Actions/Services)."
