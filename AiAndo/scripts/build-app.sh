#!/usr/bin/env bash
# Build a self-contained app. Use --install to also copy it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_ROOT="$(pwd)/.."
TASK_NODE="$(command -v node)"
TASK_NODE_MAJOR="$($TASK_NODE -p 'process.versions.node.split(".")[0]')"
if [ "$TASK_NODE_MAJOR" -lt 22 ]; then
  echo "Node 22 or newer is required to build the AI runner." >&2
  exit 1
fi
(cd "$TASK_ROOT/server" && npm ci && npm run bundle:desktop)
swift build -c release
TASK_BIN="$(swift build -c release --show-bin-path)/AiAndo"
TASK_APP="build/AiAndo.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
cp "$TASK_BIN" "$TASK_APP/Contents/MacOS/AiAndo"
cp "$TASK_NODE" "$TASK_APP/Contents/Resources/node"
cp "$TASK_ROOT/server/dist/ai-worker.cjs" "$TASK_APP/Contents/Resources/ai-worker.cjs"
cp "$TASK_ROOT/prompts/ai-ando-system-prompt.md" "$TASK_APP/Contents/Resources/"
cp "$TASK_ROOT/prompt-overlay/hooks/prompt-mirror.py" "$TASK_APP/Contents/Resources/"
cat > "$TASK_APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>AiAndo</string>
  <key>CFBundleIdentifier</key><string>com.aiando.overlay</string>
  <key>CFBundleExecutable</key><string>AiAndo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$TASK_APP/Contents/Resources/node"
codesign --force --sign - "$TASK_APP"
if [ "${1:-}" = "--install" ]; then
  mkdir -p "$HOME/Applications"
  ditto "$TASK_APP" "$HOME/Applications/AiAndo.app"
  echo "Installed $HOME/Applications/AiAndo.app. Open it and click Install in Cursor."
else
  echo "Built $TASK_APP. Open it and click Install in Cursor."
fi
