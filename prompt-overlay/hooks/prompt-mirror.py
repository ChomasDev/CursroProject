#!/usr/bin/env python3
"""Log prompt, thought, tools, reply, stop. Stamp duration. Never block chat."""

import fcntl
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

ROOT = Path.home() / ".cursor" / "prompt-mirror"
LOG = ROOT / "events.jsonl"
STATE = ROOT / "timing.json"
TEXT_CAP = 4000
OUT_CAP = 800


def lock_file(handle) -> None:
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)


def unlock_file(handle) -> None:
    fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def clip(value, cap: int) -> str:
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False)
    if len(text) <= cap:
        return text
    return text[: cap - 1] + "…"


def first_str(payload: dict, *keys: str) -> str:
    for key in keys:
        value = payload.get(key)
        if isinstance(value, str) and value:
            return value
        if isinstance(value, dict):
            nested = value.get("name") or value.get("tool_name") or value.get("type")
            if isinstance(nested, str) and nested:
                return nested
    return ""


def tool_name(payload: dict) -> str:
    return first_str(
        payload,
        "tool_name",
        "tool_type",
        "tool",
        "name",
        "mcp_tool_name",
    ) or "unknown"


def tool_input(payload: dict):
    for key in ("tool_input", "input", "arguments", "command", "updated_input"):
        if key in payload and payload[key] not in (None, ""):
            return payload[key]
    return None


def tool_output(payload: dict):
    for key in ("tool_output", "output", "result", "error"):
        if key in payload and payload[key] not in (None, ""):
            return payload[key]
    return None


def classify(name: str) -> str:
    return {
        "beforeSubmitPrompt": "prompt",
        "afterAgentThought": "thought",
        "preToolUse": "tool_start",
        "postToolUse": "tool_end",
        "postToolUseFailure": "tool_fail",
        "afterAgentResponse": "response",
        "stop": "stop",
    }.get(name, name or "event")


def text_for(name: str, payload: dict) -> str:
    if name == "beforeSubmitPrompt":
        return clip(payload.get("prompt") or "", TEXT_CAP)
    if name == "afterAgentThought":
        return clip(
            payload.get("text")
            or payload.get("thought")
            or payload.get("reasoning")
            or "",
            TEXT_CAP,
        )
    if name == "afterAgentResponse":
        return clip(payload.get("text") or payload.get("response") or "", TEXT_CAP)
    if name in {"preToolUse", "postToolUse", "postToolUseFailure"}:
        blob = tool_input(payload) if name == "preToolUse" else tool_output(payload) or ""
        return clip(blob, OUT_CAP)
    if name == "stop":
        return clip(payload.get("status") or payload.get("reason") or "", OUT_CAP)
    return clip(payload.get("prompt") or payload.get("text") or "", TEXT_CAP)


def attachments_of(payload: dict) -> list:
    items = []
    for item in payload.get("attachments") or []:
        if isinstance(item, dict):
            items.append({"type": item.get("type"), "file_path": item.get("file_path")})
    return items


def apply_timing(name: str, payload: dict, now: float) -> dict:
    conv = str(payload.get("conversation_id") or "")
    gen = str(payload.get("generation_id") or "")
    extra = {}
    ROOT.mkdir(parents=True, exist_ok=True)
    with STATE.open("a+", encoding="utf-8") as handle:
        lock_file(handle)
        handle.seek(0)
        raw = handle.read()
        try:
            state = json.loads(raw) if raw.strip() else {"turns": {}, "tools": []}
        except json.JSONDecodeError:
            state = {"turns": {}, "tools": []}
        if not isinstance(state, dict):
            state = {"turns": {}, "tools": []}
        turns = state.setdefault("turns", {})
        tools = state.setdefault("tools", [])

        if name == "beforeSubmitPrompt" and conv:
            turns[conv] = {"ts": now, "generation_id": gen}

        if name == "preToolUse":
            tools.append(
                {
                    "ts": now,
                    "conversation_id": conv,
                    "generation_id": gen,
                    "tool": tool_name(payload),
                }
            )
            if len(tools) > 200:
                state["tools"] = tools[-200:]

        if name in {"postToolUse", "postToolUseFailure"}:
            tname = tool_name(payload)
            match = None
            for index in range(len(tools) - 1, -1, -1):
                item = tools[index]
                if item.get("tool") != tname:
                    continue
                if conv and item.get("conversation_id") and item.get("conversation_id") != conv:
                    continue
                match = tools.pop(index)
                break
            if match:
                extra["duration_ms"] = int((now - float(match["ts"])) * 1000)
                extra["since"] = "tool_start"

        if name == "stop" and conv and conv in turns:
            extra["duration_ms"] = int((now - float(turns[conv]["ts"])) * 1000)
            extra["since"] = "prompt"
            extra["turn_complete"] = True

        handle.seek(0)
        handle.truncate()
        handle.write(json.dumps(state))
        handle.flush()
        unlock_file(handle)
    return extra


def emit(payload: dict) -> None:
    name = str(payload.get("hook_event_name") or "")
    now = time.time()
    extra = apply_timing(name, payload, now)
    event = {
        "id": uuid.uuid4().hex,
        "ts": now,
        "iso": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now)),
        "kind": classify(name),
        "hook_event_name": name,
        "text": text_for(name, payload),
        "conversation_id": payload.get("conversation_id"),
        "generation_id": payload.get("generation_id"),
        "model": payload.get("model"),
        "workspace_roots": payload.get("workspace_roots") or [],
        "attachments": attachments_of(payload),
    }
    if name in {"preToolUse", "postToolUse", "postToolUseFailure"}:
        event["tool"] = tool_name(payload)
    event.update(extra)

    ROOT.mkdir(parents=True, exist_ok=True)
    line = json.dumps(event, ensure_ascii=False) + "\n"
    with LOG.open("a", encoding="utf-8") as handle:
        lock_file(handle)
        handle.write(line)
        handle.flush()
        unlock_file(handle)


def ensure_overlay() -> None:
    app = Path.home() / "Applications" / "AiAndo.app"
    if app.exists():
        running = subprocess.run(["/usr/bin/pgrep", "-x", "AiAndo"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if running.returncode == 0:
            return
        subprocess.Popen(
            ["/usr/bin/open", "-g", str(app), "--args", "--background"],
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def finish(name: str) -> None:
    if name == "beforeSubmitPrompt":
        sys.stdout.write('{"continue": true}\n')
    elif name == "preToolUse":
        sys.stdout.write("{}\n")
    else:
        sys.stdout.write("{}\n")


def main() -> None:
    raw = sys.stdin.read()
    name = ""
    try:
        payload = json.loads(raw) if raw.strip() else {}
        if not isinstance(payload, dict):
            payload = {}
        name = str(payload.get("hook_event_name") or "")
        emit(payload)
        if name == "beforeSubmitPrompt":
            ensure_overlay()
    except Exception as exc:
        sys.stderr.write(f"prompt-mirror: {exc}\n")
    finish(name)


if __name__ == "__main__":
    main()
