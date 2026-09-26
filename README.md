# Ai-Ando

A macOS app that roasts your prompts while Cursor works. One home page, provider settings, and the original large-text overlay. Requires macOS 14 or newer.

## Build and use

Build with Xcode command-line tools, Node 22+, and npm:

```sh
./AiAndo/scripts/build-app.sh
open AiAndo/build/AiAndo.app
```

1. Open the app. By default it uses **Cursor** as its AI, so no API key is needed. On first launch it installs the [Cursor CLI](https://cursor.com/docs/cli/installation) (`agent`, in `~/.local/bin`) if it is missing and opens your browser so you can approve Ai-Ando with your Cursor account. You only do this once.
2. Click **Install in Cursor**. This copies the app into `~/Applications`, installs its hook, merges your global Cursor configuration, and backs up the original.
3. Restart Cursor, then submit a prompt. Ai-Ando starts in the background and shows the overlay. Close it with Escape, Command-L, or its close button.

### Using Cursor as the AI

Roasts run through `agent -p` on the user's own Cursor plan, so they count toward that plan's usage. Each call runs in an empty temporary folder without `--force`, so the agent cannot touch your projects. If sign-in is missing or expires, the next roast starts it again, and **Settings → Cursor account → Connect Cursor** does the same by hand. The model defaults to `auto`; you can enter any model listed by `agent models`. Expect a few extra seconds per roast compared with a direct API call.

### Using your own API key (optional)

Open **Settings**, choose Anthropic, OpenAI, Google, or OpenRouter, paste that provider's API key, and pick a model. **Test connection** makes a small paid API request; **Save settings** applies it to subsequent roasts.

**Preview the roast** plays sample content without any AI call. The app stays in the menu bar; click the skull to reopen it or access Settings.

The built app includes Node and a bundled Vercel AI SDK worker. End users do not need Node, npm, or a running server. With Cursor, the worker calls the Cursor CLI and no key is stored. API keys for other providers are stored per provider in macOS Keychain and passed to the worker through private stdin, never through files, URLs, or process arguments. The worker sends prompts to the selected provider. Cursor hooks use `/usr/bin/python3` (available with Apple's command-line tools).

## Development

- `AiAndo/Sources/AiAndo/App`: lifecycle and session coordination.
- `AiAndo/Sources/AiAndo/Settings`: provider preferences, Keychain, Cursor hook installation, and Cursor CLI setup/sign-in (`CursorAgent.swift`).
- `AiAndo/Sources/AiAndo/UI`: app page, Settings, overlay playback, and summary.
- `server/src/desktop.ts`: bundled runner using the same roast service as the optional server.
- `server/src/services/ai.service.ts`: provider selection, generation, JSON validation, and safe errors.
- `server/src/services/cursor.service.ts`: headless Cursor CLI calls for the default no-key provider.
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
