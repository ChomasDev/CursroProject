# Ai-Ando

A macOS app that roasts your prompts while Cursor works. One home page, provider settings, and the original large-text overlay. Requires macOS 14 or newer.

## Build and use

Build with Xcode command-line tools, Node 22+, and npm:

```sh
./AiAndo/scripts/build-app.sh
open AiAndo/build/AiAndo.app
```

1. Open **Settings**, choose Anthropic, OpenAI, Google, or OpenRouter, and paste that provider's API key.
2. Pick a suggested model or enter any supported model ID. **Test connection** makes a small paid API request; **Save settings** applies it to subsequent roasts.
3. Click **Install in Cursor**. This copies the app into `~/Applications`, installs its hook, merges your global Cursor configuration, and backs up the original.
4. Restart Cursor, then submit a prompt. Ai-Ando starts in the background and shows the overlay. Close it with Escape, Command-L, or its close button.

**Preview the roast** plays sample content without an API key. The app stays in the menu bar; click the skull to reopen it or access Settings.

The built app includes Node and a bundled Vercel AI SDK worker. End users do not need Node, npm, or a running server. Keys are stored per provider in macOS Keychain and passed to the worker through private stdin, never through files, URLs, or process arguments. The worker sends prompts to the selected provider. Cursor hooks use `/usr/bin/python3` (available with Apple's command-line tools).

## Development

- `AiAndo/Sources/AiAndo/App`: lifecycle and session coordination.
- `AiAndo/Sources/AiAndo/Settings`: provider preferences, Keychain, and Cursor installation.
- `AiAndo/Sources/AiAndo/UI`: app page, Settings, overlay playback, and summary.
- `server/src/desktop.ts`: bundled runner using the same roast service as the optional server.
- `server/src/services/ai.service.ts`: Vercel AI SDK provider selection, generation, JSON validation, and safe errors.
- `prompt-overlay/hooks/prompt-mirror.py`: nonblocking Cursor event logger and background launcher.

```sh
cd server
npm ci
npm run build
npm test
npm run bundle:desktop
```

```sh
cd AiAndo
swift test
```

The optional Express/WebSocket server remains available for shared LAN use with its existing `.env` configuration. To use a LAN backend instead of a personal provider key, launch the app with `AIANDO_WS_URL=ws://your-server:3000/roast`. Personal API keys are never sent to a LAN server. The desktop runner stores local leaderboard data in `~/Library/Application Support/AiAndo/leaderboard.json`; the comparison includes fictional bot entries and the similar-prompt count is a gag, not measured usage.

The repo's project-local hooks are empty to avoid duplicate events after global installation. Remove any older Ai-Ando hooks from other projects if they duplicate your global hook. Historical pitch assets and the legacy Python overlay are retained but are not packaged or launched by the app.

The build is signed locally for development, not notarized for public distribution, and targets the architecture of the build machine.
