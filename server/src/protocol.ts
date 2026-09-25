import { AndoError } from "./errors";

export type Incoming =
  | { type: "user"; text: string; userId?: string }
  | { type: "assistant"; text: string }
  | { type: "done"; text?: string };

const ASSISTANT = new Set(["assistant", "ai", "response"]);

export function parseIncoming(raw: string, hasSession: boolean): Incoming {
  const trimmed = raw.trim();
  if (!trimmed) throw new AndoError("Messaggio vuoto", 400);
  if (trimmed === "done" || trimmed === "[DONE]") return { type: "done" };
  if (trimmed.startsWith("{")) {
    try {
      const parsed: unknown = JSON.parse(trimmed);
      if (parsed && typeof parsed === "object") {
        return fromObject(parsed as Record<string, unknown>, hasSession);
      }
    } catch {
      // Plain text that happens to start with "{".
    }
  }
  if (!hasSession) return { type: "user", text: trimmed };
  return { type: "assistant", text: trimmed };
}

export function parseBody(body: unknown, hasSession: boolean): Incoming {
  if (typeof body === "string") return parseIncoming(body, hasSession);
  if (!body || typeof body !== "object") throw new AndoError("Manca il testo", 400);
  return fromObject(body as Record<string, unknown>, hasSession);
}

export function sessionIdOf(body: unknown): string | undefined {
  if (!body || typeof body !== "object") return undefined;
  const value = (body as Record<string, unknown>).sessionId;
  return typeof value === "string" && value.trim() ? value.trim() : undefined;
}

function fromObject(body: Record<string, unknown>, hasSession: boolean): Incoming {
  const text = readText(body);
  const userId = typeof body.userId === "string" ? body.userId : undefined;
  const marker = stringOf(body.type) ?? stringOf(body.role);
  const finishing =
    body.done === true || marker === "done" || marker === "stop";

  if (finishing) return { type: "done", text };
  if (marker === "user" || (!marker && !hasSession)) {
    if (!text) throw new AndoError("Manca il testo dell'utente", 400);
    return { type: "user", text, userId };
  }
  if (marker && ASSISTANT.has(marker)) {
    if (!text) throw new AndoError("Manca il testo della risposta", 400);
    return { type: "assistant", text };
  }
  if (!text) throw new AndoError("Manca il testo", 400);
  return { type: "assistant", text };
}

function readText(body: Record<string, unknown>): string | undefined {
  for (const key of ["text", "userText", "prompt", "content", "message"]) {
    const value = body[key];
    if (typeof value === "string" && value.trim()) return value.trim();
  }
  return undefined;
}

function stringOf(value: unknown): string | undefined {
  return typeof value === "string" && value.trim() ? value.trim().toLowerCase() : undefined;
}
