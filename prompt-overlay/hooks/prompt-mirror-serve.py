#!/usr/bin/env python3
"""Local window for prompts and agent replies. Listens on 127.0.0.1 only."""

import json
import queue
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HOST = "127.0.0.1"
PORT = 47321
LOG = Path.home() / ".cursor" / "prompt-mirror" / "events.jsonl"
KEEP = 400

PAGE = r"""<!DOCTYPE html>
<html lang="it">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Prompt Mirror</title>
<style>
  :root {
    color-scheme: dark;
    --bg: #101311;
    --card: #181d1b;
    --line: #2c3531;
    --text: #e8f0eb;
    --muted: #8d9c95;
    --prompt: #3dd68c;
    --response: #8eb7ff;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    min-height: 100vh;
    background:
      radial-gradient(900px 420px at 10% -10%, rgba(61, 214, 140, 0.08), transparent 60%),
      var(--bg);
    color: var(--text);
    font: 15px/1.45 "SF Pro Text", ui-sans-serif, system-ui, sans-serif;
  }
  header {
    position: sticky;
    top: 0;
    z-index: 2;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    padding: 16px 22px;
    background: rgba(16, 19, 17, 0.9);
    border-bottom: 1px solid var(--line);
    backdrop-filter: blur(10px);
  }
  h1 { margin: 0; font-size: 16px; font-weight: 620; letter-spacing: -0.02em; }
  .status { display: flex; align-items: center; gap: 8px; color: var(--muted); font-size: 13px; }
  .dot {
    width: 8px; height: 8px; border-radius: 99px; background: #5c6b64;
  }
  .dot.on { background: var(--prompt); box-shadow: 0 0 0 4px rgba(61, 214, 140, 0.15); }
  button {
    border: 1px solid var(--line);
    background: transparent;
    color: var(--text);
    border-radius: 999px;
    padding: 6px 12px;
    font: inherit;
    cursor: pointer;
  }
  button:hover { border-color: #4d5c56; }
  main { max-width: 820px; margin: 0 auto; padding: 22px; }
  .empty { color: var(--muted); padding: 48px 0; }
  article {
    background: var(--card);
    border: 1px solid var(--line);
    border-left-width: 3px;
    border-radius: 14px;
    padding: 14px 16px 12px;
    margin: 0 0 12px;
  }
  article.prompt { border-left-color: var(--prompt); }
  article.response { border-left-color: var(--response); }
  .meta {
    display: flex;
    gap: 10px;
    align-items: baseline;
    color: var(--muted);
    font-size: 12px;
    margin-bottom: 8px;
  }
  .kind { color: var(--text); font-weight: 600; letter-spacing: 0.04em; text-transform: uppercase; font-size: 11px; }
  article.prompt .kind { color: var(--prompt); }
  article.response .kind { color: var(--response); }
  pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    font: 14px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
  }
  .files { margin-top: 8px; color: var(--muted); font-size: 12px; }
</style>
</head>
<body>
<header>
  <div>
    <h1>Prompt Mirror</h1>
  </div>
  <div class="status">
    <span id="dot" class="dot"></span>
    <span id="state">connessione…</span>
    <button id="clear" type="button">Svuota</button>
  </div>
</header>
<main id="feed"><p class="empty">In attesa del prossimo messaggio inviato in Cursor.</p></main>
<script>
const feed = document.getElementById("feed");
const dot = document.getElementById("dot");
const state = document.getElementById("state");
const seen = new Set();

function when(ts) {
  return new Date(ts * 1000).toLocaleString("it-IT", {
    hour: "2-digit", minute: "2-digit", second: "2-digit", day: "2-digit", month: "2-digit"
  });
}

function add(ev, stick) {
  if (!ev || !ev.id || seen.has(ev.id)) return;
  seen.add(ev.id);
  const empty = feed.querySelector(".empty");
  if (empty) empty.remove();
  const card = document.createElement("article");
  card.className = ev.kind === "response" ? "response" : "prompt";
  const meta = document.createElement("div");
  meta.className = "meta";
  const kind = document.createElement("span");
  kind.className = "kind";
  kind.textContent = ev.kind === "response" ? "Risposta" : "Prompt";
  const time = document.createElement("span");
  time.textContent = when(ev.ts || Date.now() / 1000);
  meta.append(kind, time);
  if (ev.model) {
    const model = document.createElement("span");
    model.textContent = ev.model;
    meta.append(model);
  }
  const body = document.createElement("pre");
  body.textContent = ev.text || "";
  card.append(meta, body);
  const files = (ev.attachments || []).map(a => a.file_path).filter(Boolean);
  if (files.length) {
    const extra = document.createElement("div");
    extra.className = "files";
    extra.textContent = files.join("\n");
    card.append(extra);
  }
  const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
  feed.append(card);
  if (stick || nearBottom) card.scrollIntoView({ block: "end" });
}

async function history() {
  const res = await fetch("/api/events");
  const rows = await res.json();
  rows.forEach(ev => add(ev, false));
  if (rows.length) window.scrollTo(0, document.body.scrollHeight);
}

function connect() {
  const source = new EventSource("/api/stream");
  source.onopen = () => {
    dot.classList.add("on");
    state.textContent = "in ascolto";
  };
  source.onmessage = (msg) => {
    add(JSON.parse(msg.data), true);
  };
  source.onerror = () => {
    dot.classList.remove("on");
    state.textContent = "riconnessione…";
    source.close();
    setTimeout(connect, 1000);
  };
}

document.getElementById("clear").onclick = async () => {
  await fetch("/api/clear", { method: "POST" });
  seen.clear();
  feed.innerHTML = '<p class="empty">In attesa del prossimo messaggio inviato in Cursor.</p>';
};

history().then(connect);
</script>
</body>
</html>
"""


class Hub:
    def __init__(self) -> None:
        self.events: list[dict] = []
        self.offset = 0
        self.clients: list[queue.Queue] = []
        self.lock = threading.Lock()

    def push(self, event: dict) -> None:
        with self.lock:
            self.events.append(event)
            del self.events[:-KEEP]
            clients = list(self.clients)
        for client in clients:
            client.put(event)

    def snapshot(self) -> list[dict]:
        with self.lock:
            return list(self.events)

    def clear(self) -> None:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        LOG.write_text("", encoding="utf-8")
        with self.lock:
            self.events.clear()
            self.offset = 0


HUB = Hub()


def load_existing() -> None:
    if not LOG.exists():
        return
    lines = LOG.read_text(encoding="utf-8").splitlines()
    for line in lines[-KEEP:]:
        try:
            HUB.events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    HUB.offset = LOG.stat().st_size


def watch() -> None:
    while True:
        try:
            if not LOG.exists():
                time.sleep(0.15)
                continue
            size = LOG.stat().st_size
            if size < HUB.offset:
                HUB.offset = 0
            if size == HUB.offset:
                time.sleep(0.12)
                continue
            with LOG.open("r", encoding="utf-8") as handle:
                handle.seek(HUB.offset)
                chunk = handle.read()
                HUB.offset = handle.tell()
            for line in chunk.splitlines():
                if not line.strip():
                    continue
                try:
                    HUB.push(json.loads(line))
                except json.JSONDecodeError:
                    continue
        except OSError:
            time.sleep(0.2)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args) -> None:
        return

    def _send(self, code: int, body: bytes, content_type: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        if self.path in ("/", "/index.html"):
            self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
            return
        if self.path == "/health":
            self._send(200, b"ok", "text/plain")
            return
        if self.path == "/api/events":
            body = json.dumps(HUB.snapshot(), ensure_ascii=False).encode("utf-8")
            self._send(200, body, "application/json; charset=utf-8")
            return
        if self.path == "/api/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            client: queue.Queue = queue.Queue()
            with HUB.lock:
                HUB.clients.append(client)
            try:
                while True:
                    try:
                        event = client.get(timeout=12)
                    except queue.Empty:
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                        continue
                    data = json.dumps(event, ensure_ascii=False).encode("utf-8")
                    self.wfile.write(b"data: " + data + b"\n\n")
                    self.wfile.flush()
            except (BrokenPipeError, ConnectionResetError, OSError):
                pass
            finally:
                with HUB.lock:
                    if client in HUB.clients:
                        HUB.clients.remove(client)
            return
        self._send(404, b"not found", "text/plain")

    def do_POST(self) -> None:
        if self.path == "/api/clear":
            HUB.clear()
            self._send(200, b"{}", "application/json")
            return
        self._send(404, b"not found", "text/plain")


def main() -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    load_existing()
    threading.Thread(target=watch, daemon=True).start()
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"http://{HOST}:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
