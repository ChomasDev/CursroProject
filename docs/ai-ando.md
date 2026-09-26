# Ai-Ando architecture

Ai-Ando is a native macOS 14+ menu-bar app. Its main window contains a minimal home page and a Settings page. The full-screen overlay retains its large text, streaming phrase playback, and final session summary.

## Normal desktop flow

Cursor hook → `~/.cursor/prompt-mirror/events.jsonl` → `EventLogWatcher` → `Coordinator` → bundled AI SDK worker → overlay.

The installer copies the `.app` into `~/Applications`, copies the bundled event hook into `~/.cursor/prompt-mirror`, and merges all seven supported events into `~/.cursor/hooks.json`. Existing unrelated hooks and other fields are preserved. Each existing configuration is backed up before writing. Installation is repeatable without adding duplicate Ai-Ando hooks. Invalid configs are left untouched.

The hook logs timing, thought, tool, response, and stop events. It starts the app with `--background` only when it is not running. It never starts a Node server or launches the old Python overlay. The app replays only recent events so the first prompt is captured after launch.

## Settings and generation

`AppSettings` stores the chosen provider and per-provider model IDs in UserDefaults. `APIKeyStore` stores provider keys in macOS Keychain. The Settings page offers a secure paste field, a visibility toggle, editable model IDs, suggestions, Save, and a connection test. The test uses the unsaved form values and does not silently save them.

`LocalAIRoastService` loads a fresh configuration per turn. `AIWorker` launches the Node binary included in the app, writes a JSON request through private stdin, and decodes newline-delimited response frames. It kills the subprocess when its stream is cancelled. Credentials are never written to disk, argv, or inherited environment variables. The provider may retain prompts according to its own policy.

The worker calls `finishRoast` and `writeRoast`, with `generateText` from Vercel's AI SDK. Anthropic, OpenAI, Google, and OpenRouter use their respective provider adapters. Responses are validated against the existing roast schema, with one repair attempt for invalid JSON. Provider errors are displayed without echoing upstream response bodies or credentials. A connection test is an explicit, small paid generation request.

Local leaderboard data lives outside the app bundle, in Application Support. Statistics and humorous comparisons are computed before generation. Fictional bot entries and random similar-prompt counts are entertainment, not real global analytics. Secret detection short-circuits generation when a prompt appears to contain credentials. Desktop use does not need a Perplexity key or server configuration.

## Optional LAN mode

The Express server and `/roast` WebSocket endpoint remain compatible with existing clients and `.env` configuration. `AIANDO_WS_URL` opts into a shared backend when no personal key is configured. Personal provider keys are never included in WebSocket requests. See [WEBSOCKET_PROTOCOL.md](../AiAndo/WEBSOCKET_PROTOCOL.md) for the frame contract.

## Build and verification

`AiAndo/scripts/build-app.sh` installs locked JavaScript dependencies, bundles `server/src/desktop.ts`, builds Swift, and packages the Node executable, AI runner, system prompt, and Cursor hook in the app's Resources. It signs the binaries locally. Add `--install` to also copy the build into `~/Applications`; global Cursor hooks are installed through the app button.

Swift tests cover event UI behavior and safe, repeatable hook installation. Node tests mock provider APIs to verify endpoint, model, authentication, JSON repair, and credential-safe errors. Real provider verification requires a user-owned API key. See [README](../README.md) for commands.
