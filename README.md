# Ai-Ando

A macOS app that roasts your prompts while Cursor works. One home page, provider settings, and the original large-text overlay. Requires macOS 14 or newer.

## Install and start (one command)

Open **Terminal** (press `Cmd + Space`, type "Terminal", press Enter), paste this line, and press Enter:

```sh
curl -fsSL https://raw.githubusercontent.com/ChomasDev/CursroProject/main/install.sh | bash
```

That's it. The command installs Ai-Ando, opens it, and connects it to Cursor. **Then open Cursor, write your first prompt, and watch it get roasted.** 💀

The first time, two things may pop up:

- **A browser page from Cursor:** click to approve Ai-Ando. It uses your Cursor plan, so no API key is needed. You only do this once.
- **"Restart Cursor now?"** in Terminal: press Enter. Cursor needs one restart to load Ai-Ando.

Close a roast with Escape, Command-L, or its close button. Ai-Ando lives in the menu bar (the 💀); click it to open the app, pick a different model, or preview a roast.

**To update**, run the same command again.

<details>
<summary>What the command does</summary>

1. Checks you have Apple's command-line tools. If not, a macOS window opens to install them: accept, wait, then run the command again.
2. Uses your Node.js 22+ if you have it. Otherwise it downloads a private copy from nodejs.org, checksum-verified, without touching your system.
3. Downloads the Ai-Ando source into `~/.aiando/src`.
4. Builds the app on your Mac and installs it in `~/Applications` (build log: `~/.aiando/build.log`).
5. Opens Ai-Ando, installs its Cursor hooks (keeping a backup of your `~/.cursor/hooks.json`), sets up the Cursor CLI, and offers to restart Cursor.

You can read [install.sh](install.sh) before running it.
</details>

## Manual install (step by step)

Requirements: macOS 14 or newer, Apple's command-line tools (`xcode-select --install`), and Node 22+.

1. Download the code:
   ```sh
   git clone https://github.com/ChomasDev/CursroProject.git
   cd CursroProject
   ```
2. Build the app:
   ```sh
   ./AiAndo/scripts/build-app.sh --install
   ```
3. Open it:
   ```sh
   open ~/Applications/AiAndo.app
   ```
4. Ai-Ando installs the [Cursor CLI](https://cursor.com/docs/cli/installation) (`agent`, in `~/.local/bin`) if it is missing and opens your browser. **Approve Ai-Ando** with your Cursor account; you only do this once.
5. On the app's home page, click **Install in Cursor**. This installs the hook and merges your global Cursor configuration, keeping a backup of the original.
6. **Restart Cursor** and send a prompt.

## Using Cursor as the AI

Roasts run through `agent -p` on the user's own Cursor plan, so they count toward that plan's usage. Each call runs in an empty temporary folder without `--force`, so the agent cannot touch your projects. If sign-in is missing or expires, the next roast starts it again, and **Settings → Cursor account → Connect Cursor** does the same by hand. The model defaults to `auto`; **Settings → Model** lists every model your Cursor account can use, with search. Ai-Ando uses its own Cursor CLI config (`~/Library/Application Support/AiAndo/cursor-cli`) with HTTP/1 enabled, because the CLI's default HTTP/2 connection drops on many networks; your own `~/.cursor/cli-config.json` is not changed. Expect a few extra seconds per roast compared with a direct API call.

## Using your own API key (optional)

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
