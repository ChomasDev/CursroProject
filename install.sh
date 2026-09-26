#!/usr/bin/env bash
# One-command install: downloads Ai-Ando, builds it, installs it in ~/Applications,
# connects it to Cursor, and opens it. Safe to run again to update.
set -euo pipefail

REPO="https://github.com/ChomasDev/CursroProject.git"
SRC="${AIANDO_SRC:-$HOME/.aiando/src}"
TOOLS="$HOME/.aiando/tools"
step() { printf '\n\033[1;35m==>\033[0m \033[1m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mError:\033[0m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Ai-Ando runs on macOS only."
[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "Ai-Ando needs macOS 14 or newer."

step "1/5 Checking Apple's command-line tools"
if ! xcode-select -p >/dev/null 2>&1 || ! command -v swift >/dev/null 2>&1; then
  xcode-select --install >/dev/null 2>&1 || true
  fail "Install Apple's command-line tools in the window that just opened, then run this command again."
fi

step "2/5 Checking Node.js 22+"
node_ok() { command -v node >/dev/null 2>&1 && [ "$(node -p 'process.versions.node.split(".")[0]')" -ge 22 ]; }
[ -d "$TOOLS/node/bin" ] && export PATH="$TOOLS/node/bin:$PATH"
if ! node_ok; then
  # Private copy from nodejs.org, checksum-verified; your system Node is left alone.
  arch="$(uname -m)"; [ "$arch" = "x86_64" ] && arch="x64"
  base="https://nodejs.org/dist/latest-v22.x"
  line="$(curl -fsSL "$base/SHASUMS256.txt" | grep "darwin-$arch.tar.gz$")" || fail "Could not reach nodejs.org."
  sum="${line%% *}"; file="${line##* }"
  mkdir -p "$TOOLS"; tmp="$(mktemp -d)"
  curl -fsSL "$base/$file" -o "$tmp/$file"
  [ "$(shasum -a 256 "$tmp/$file" | cut -d' ' -f1)" = "$sum" ] || fail "Node.js download failed its checksum."
  rm -rf "$TOOLS/node"; mkdir -p "$TOOLS/node"
  tar -xzf "$tmp/$file" -C "$TOOLS/node" --strip-components 1
  rm -rf "$tmp"
  export PATH="$TOOLS/node/bin:$PATH"
  node_ok || fail "Node.js 22 could not be set up."
fi

step "3/5 Downloading Ai-Ando"
if [ -d "$SRC/.git" ]; then
  git -C "$SRC" pull --ff-only --quiet
else
  mkdir -p "$(dirname "$SRC")"
  git clone --quiet "$REPO" "$SRC" || fail "Could not download Ai-Ando. Make sure your GitHub account has access to the repository."
fi

step "4/5 Building and installing (takes a minute or two)"
mkdir -p "$HOME/.aiando"
pkill -x AiAndo 2>/dev/null || true
"$SRC/AiAndo/scripts/build-app.sh" --install >"$HOME/.aiando/build.log" 2>&1 \
  || fail "Build failed. Details: $HOME/.aiando/build.log"

step "5/5 Opening Ai-Ando"
open "$HOME/Applications/AiAndo.app" --args --setup
cat <<'DONE'

Done! Last steps:
  1. Your browser opens Cursor: click to approve Ai-Ando (one time only).
  2. Restart Cursor.
  3. Send any prompt in Cursor and enjoy the roast.

Run the same command again any time to update.
DONE
