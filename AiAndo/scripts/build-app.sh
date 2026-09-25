#!/usr/bin/env bash
# Build AiAndo.app (menu-bar only, no Dock icon) and install it in ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/AiAndo"

APP="build/AiAndo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/AiAndo"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AiAndo</string>
  <key>CFBundleIdentifier</key><string>com.aiando.overlay</string>
  <key>CFBundleExecutable</key><string>AiAndo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/AiAndo.app"
cp -R "$APP" "$HOME/Applications/AiAndo.app"
echo "Installed $HOME/Applications/AiAndo.app"
