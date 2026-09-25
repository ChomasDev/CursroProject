#!/usr/bin/env python3
"""Fullscreen click-through flash when a Cursor prompt is submitted."""

import fcntl
import json
import os
import sys
import time
import traceback
from pathlib import Path

import objc
from AppKit import (
    NSApplication,
    NSApplicationActivationPolicyAccessory,
    NSBackingStoreBuffered,
    NSColor,
    NSScreen,
    NSScreenSaverWindowLevel,
    NSWindow,
    NSWindowCollectionBehaviorCanJoinAllSpaces,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowCollectionBehaviorIgnoresCycle,
    NSWindowCollectionBehaviorStationary,
    NSWindowStyleMaskBorderless,
    NSWorkspace,
    NSZeroRect,
)
from PyObjCTools import AppHelper

objc.loadBundle(
    "WebKit",
    globals(),
    bundle_path="/System/Library/Frameworks/WebKit.framework",
)

ROOT = Path.home() / ".cursor" / "prompt-mirror"
LOG = ROOT / "events.jsonl"
PID = ROOT / "overlay.pid"
ERR = ROOT / "overlay.log"
FRESH_SEC = 3.0
END_KINDS = {"stop", "response"}

PAGE = r"""<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<style>
  :root {
    --ease-out: cubic-bezier(0.23, 1, 0.32, 1);
    --ease-in: cubic-bezier(0.55, 0, 1, 0.45);
    --ease-move: cubic-bezier(0.77, 0, 0.175, 1);
    --green: #3dd68c;
    --ink: #f4f7f5;
  }
  * { box-sizing: border-box; }
  html, body {
    margin: 0;
    width: 100%;
    height: 100%;
    background: transparent;
    color: var(--ink);
    font-family: "SF Pro Display", "SF Pro Text", -apple-system, BlinkMacSystemFont, sans-serif;
    -webkit-font-smoothing: antialiased;
    user-select: none;
    cursor: none;
  }
  #root {
    position: fixed;
    inset: 0;
    display: grid;
    place-items: center;
    pointer-events: none;
    overflow: hidden;
  }
  .veil, .glow, .ring, .sweep { position: absolute; }
  .veil {
    inset: 0;
    background:
      radial-gradient(880px 520px at 50% 46%, rgba(61, 214, 140, 0.18), transparent 64%),
      rgba(8, 12, 10, 0.84);
    opacity: 0;
  }
  .glow {
    width: min(68vw, 820px);
    height: min(68vw, 820px);
    border-radius: 50%;
    background: radial-gradient(circle, rgba(61, 214, 140, 0.2), transparent 68%);
    opacity: 0;
    transform: scale(0.94);
  }
  .ring {
    width: min(34vw, 460px);
    aspect-ratio: 1;
    border-radius: 50%;
    border: 1px solid rgba(61, 214, 140, 0.7);
    opacity: 0;
    transform: scale(0.94);
  }
  .sweep {
    left: 8%;
    right: 8%;
    top: 50%;
    height: 1px;
    background: linear-gradient(90deg, transparent, var(--green), transparent);
    opacity: 0;
    transform: translateX(-12%);
  }
  .copy {
    position: relative;
    z-index: 2;
    width: min(920px, 78vw);
    text-align: center;
    opacity: 0;
    transform: translateY(12px) scale(0.97);
  }
  .kicker {
    margin: 0;
    color: var(--green);
    font-size: 13px;
    font-weight: 600;
    letter-spacing: 0.24em;
    text-transform: uppercase;
  }
  .rule {
    width: 72px;
    height: 1px;
    margin: 16px auto;
    background: var(--green);
    transform: scaleX(0.86);
    opacity: 0;
    transform-origin: center;
  }
  .prompt {
    margin: 0;
    font-size: clamp(28px, 4.2vw, 54px);
    font-weight: 560;
    letter-spacing: -0.035em;
    line-height: 1.12;
    display: -webkit-box;
    -webkit-line-clamp: 4;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .on .veil {
    animation: veil-in 240ms var(--ease-out) both;
  }
  .on .glow {
    animation: glow-in 500ms var(--ease-out) both;
  }
  .on .ring {
    animation: ring 880ms var(--ease-out) both;
  }
  .on .sweep {
    animation: sweep 700ms var(--ease-move) 80ms both;
  }
  .on .copy {
    animation: copy-in 400ms var(--ease-out) 40ms both;
  }
  .on .rule {
    animation: rule-in 400ms var(--ease-out) 90ms both;
  }
  @keyframes veil-in { from { opacity: 0; } to { opacity: 1; } }
  @keyframes veil-out { from { opacity: 1; } to { opacity: 0; } }
  @keyframes glow-in {
    from { opacity: 0; transform: scale(0.94); }
    to { opacity: 1; transform: scale(1); }
  }
  @keyframes ring {
    0% { opacity: 0; transform: scale(0.94); }
    28% { opacity: 1; }
    100% { opacity: 0; transform: scale(1.06); }
  }
  @keyframes sweep {
    0% { opacity: 0; transform: translateX(-12%); }
    18% { opacity: 1; }
    100% { opacity: 0; transform: translateX(12%); }
  }
  @keyframes copy-in {
    to { opacity: 1; transform: none; }
  }
  @keyframes copy-out {
    from { opacity: 1; transform: none; }
    to { opacity: 0; transform: translateY(8px) scale(0.98); }
  }
  @keyframes rule-in {
    to { opacity: 1; transform: scaleX(1); }
  }
  .reduced.on .veil,
  .reduced.on .copy,
  .reduced.on .rule {
    animation: none;
    opacity: 1;
    transform: none;
  }
  .reduced .glow,
  .reduced .ring,
  .reduced .sweep { display: none; }
  @media (prefers-reduced-motion: reduce) {
    .on .veil, .on .copy, .on .rule {
      animation: none;
      opacity: 1;
      transform: none;
    }
    .glow, .ring, .sweep { display: none; }
  }
</style>
</head>
<body>
<div id="root" aria-hidden="true">
  <div class="veil"></div>
  <div class="glow"></div>
  <div class="ring"></div>
  <div class="sweep"></div>
  <div class="copy">
    <p class="kicker">Inizio</p>
    <div class="rule"></div>
    <p class="prompt" id="prompt"></p>
  </div>
</div>
<script>
function clip(text) {
  const clean = String(text || "").replace(/\s+/g, " ").trim();
  if (!clean) return "Comando avviato";
  return clean.length > 180 ? clean.slice(0, 179) + "…" : clean;
}
window.play = (text, reduced) => {
  const root = document.getElementById("root");
  document.getElementById("prompt").textContent = clip(text);
  root.classList.toggle("reduced", !!reduced);
  root.classList.remove("on");
  void root.offsetWidth;
  root.classList.add("on");
};
window.play(__PROMPT_JSON__, __REDUCED__);
</script>
</body>
</html>
"""


def log(msg: str) -> None:
    try:
        ROOT.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime("%H:%M:%S")
        with ERR.open("a", encoding="utf-8") as handle:
            handle.write(f"{stamp} {msg}\n")
    except OSError:
        pass


def claim() -> None:
    ROOT.mkdir(parents=True, exist_ok=True)
    handle = PID.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    handle.seek(0)
    handle.truncate()
    handle.write(str(os.getpid()))
    handle.flush()
    globals()["_PID_HANDLE"] = handle


def reduced_motion() -> bool:
    return bool(NSWorkspace.sharedWorkspace().accessibilityDisplayShouldReduceMotion())


class OverlayWindow(NSWindow):
    def canBecomeKeyWindow(self) -> bool:
        return False

    def canBecomeMainWindow(self) -> bool:
        return False


class Overlay:
    def __init__(self) -> None:
        self.generation = 0
        self.visible = False
        screen = NSScreen.mainScreen() or NSScreen.screens()[0]
        self.window = OverlayWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            screen.frame(),
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False,
        )
        self.window.setOpaque_(False)
        self.window.setBackgroundColor_(NSColor.clearColor())
        self.window.setHasShadow_(False)
        self.window.setLevel_(NSScreenSaverWindowLevel)
        self.window.setIgnoresMouseEvents_(True)
        self.window.setHidesOnDeactivate_(False)
        self.window.setMovable_(False)
        self.window.setCollectionBehavior_(
            NSWindowCollectionBehaviorCanJoinAllSpaces
            | NSWindowCollectionBehaviorStationary
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorIgnoresCycle
        )
        config = WKWebViewConfiguration.alloc().init()
        self.web = WKWebView.alloc().initWithFrame_configuration_(NSZeroRect, config)
        self.web.setValue_forKey_(False, "drawsBackground")
        self.window.setContentView_(self.web)

    def place(self) -> None:
        screen = NSScreen.mainScreen() or NSScreen.screens()[0]
        self.window.setFrame_display_(screen.frame(), True)

    def play(self, text: str) -> None:
        self.generation += 1
        token = self.generation
        reduced = reduced_motion()
        self.place()
        self.window.orderFrontRegardless()
        payload = json.dumps(text or "", ensure_ascii=False).replace("<", "\\u003c")
        html = (
            PAGE.replace("__PROMPT_JSON__", payload).replace(
                "__REDUCED__", "true" if reduced else "false"
            )
        )
        self.visible = True
        log("play")

        def fire(expected: int = token, body: str = html) -> None:
            if self.generation == expected:
                self.web.loadHTMLString_baseURL_(body, None)

        AppHelper.callLater(0.03, fire)

    def dismiss(self) -> None:
        if not self.visible:
            return
        self.visible = False
        self.generation += 1
        self.window.orderOut_(None)
        log("hide")


def pull(offset: int, pending: str) -> tuple[int, str, list[dict]]:
    if not LOG.exists():
        return offset, pending, []
    size = LOG.stat().st_size
    if size < offset:
        # File was truncated. Jump to EOF so old prompts do not replay.
        return size, "", []
    if size == offset:
        return offset, pending, []
    with LOG.open("r", encoding="utf-8") as handle:
        handle.seek(offset)
        chunk = handle.read()
        offset = handle.tell()
    pending += chunk
    lines = pending.split("\n")
    pending = lines.pop() if lines else ""
    events: list[dict] = []
    for line in lines:
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(item, dict):
            events.append(item)
    return offset, pending, events


def route(overlay: Overlay, events: list[dict], first: bool) -> None:
    if first:
        last_prompt = None
        ended = False
        for item in events:
            kind = item.get("kind")
            if kind == "prompt":
                last_prompt = item
                ended = False
            elif kind in END_KINDS and last_prompt is not None:
                ended = True
        if last_prompt is None or ended:
            return
        age = time.time() - float(last_prompt.get("ts") or 0)
        if age <= FRESH_SEC:
            AppHelper.callAfter(overlay.play, last_prompt.get("text") or "")
        return
    for item in events:
        kind = item.get("kind")
        if kind == "prompt":
            AppHelper.callAfter(overlay.play, item.get("text") or "")
        elif kind in END_KINDS:
            AppHelper.callAfter(overlay.dismiss)


def watch(overlay: Overlay) -> None:
    offset = 0
    pending = ""
    first = True
    while True:
        try:
            offset, pending, events = pull(offset, pending)
            if events:
                route(overlay, events, first)
            first = False
        except Exception:
            log(traceback.format_exc())
            first = False
        time.sleep(0.05)


def main() -> None:
    claim()
    log("start")
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)
    overlay = Overlay()
    if "--preview" in sys.argv:
        AppHelper.callLater(
            0.35,
            overlay.play,
            "Overlay acceso. Il prossimo prompt copre lo schermo.",
        )
    import threading

    threading.Thread(target=watch, args=(overlay,), daemon=True).start()
    AppHelper.runEventLoop()


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log(traceback.format_exc())
        raise
