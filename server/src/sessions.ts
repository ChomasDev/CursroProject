import { randomUUID } from "crypto";
import { WebSocket } from "ws";
import { AndoError } from "./errors";
import { redact } from "./secrets";
import type { AndoRoast } from "./services/ai.service";
import type { TurnStats } from "./services/stats.service";

const TTL_MS = 30 * 60 * 1000;
const USER_CAP = 20_000;
const ASSISTANT_CAP = 50_000;

export type Session = {
  id: string;
  userId: string;
  userText: string;
  assistantText: string;
  startedAt: number;
  generation: number;
  finished: boolean;
  sockets: Set<WebSocket>;
  abort?: AbortController;
  draft?: TurnStats;
  draftGeneration?: number;
  job?: Promise<AndoRoast>;
  roast?: AndoRoast;
  expires?: NodeJS.Timeout;
};

const sessions = new Map<string, Session>();

export function startTurn(input: {
  session?: Session;
  userText: string;
  userId?: string;
  socket?: WebSocket;
}): Session {
  const userText = cap(input.userText.trim(), USER_CAP);
  if (!userText) throw new AndoError("Manca il testo dell'utente", 400);

  input.session?.abort?.abort();
  const session = input.session ?? blank(cleanUserId(input.userId) ?? "anon");
  const userId = cleanUserId(input.userId);
  if (userId) session.userId = userId;
  session.userText = userText;
  session.assistantText = "";
  session.startedAt = Date.now();
  session.generation += 1;
  session.finished = false;
  session.abort = new AbortController();
  session.draft = undefined;
  session.draftGeneration = undefined;
  session.job = undefined;
  session.roast = undefined;
  if (input.socket) session.sockets.add(input.socket);
  sessions.set(session.id, session);
  armExpiry(session);
  broadcast(session, {
    type: "open",
    sessionId: session.id,
    userText: redact(session.userText),
  });
  console.log(`session open ${session.id} chars=${session.userText.length}`);
  return session;
}

export function appendAssistant(session: Session, text: string): number {
  const chunk = text.trim();
  if (!chunk) return session.assistantText.length;
  if (session.finished) {
    throw new AndoError("Turno già chiuso: manda un nuovo testo utente", 409);
  }
  if (session.assistantText && chunk.startsWith(session.assistantText)) {
    session.assistantText = chunk;
  } else if (!session.assistantText) {
    session.assistantText = chunk;
  } else {
    session.assistantText = `${session.assistantText}\n${chunk}`;
  }
  if (session.assistantText.length > ASSISTANT_CAP) {
    session.assistantText = session.assistantText.slice(-ASSISTANT_CAP);
  }
  armExpiry(session);
  broadcast(session, {
    type: "assistant",
    text: redact(session.assistantText) === session.assistantText ? chunk : redact(chunk),
    chars: session.assistantText.length,
  });
  return session.assistantText.length;
}

export function getSession(id: string): Session | undefined {
  const session = sessions.get(id);
  if (session) armExpiry(session);
  return session;
}

export function requireSession(id: string): Session {
  const session = getSession(id);
  if (!session) throw new AndoError("Sessione sconosciuta", 404);
  return session;
}

export function broadcast(session: Session, payload: unknown): void {
  const data = JSON.stringify(payload);
  for (const socket of session.sockets) {
    if (socket.readyState === WebSocket.OPEN) socket.send(data);
  }
}

export function snapshot(session: Session): Record<string, unknown> {
  return {
    type: "open",
    sessionId: session.id,
    userText: redact(session.userText),
    assistantText: redact(session.assistantText),
    ...(session.roast ? { roast: session.roast } : {}),
  };
}

function blank(userId: string): Session {
  return {
    id: randomUUID(),
    userId,
    userText: "",
    assistantText: "",
    startedAt: Date.now(),
    generation: 0,
    finished: false,
    sockets: new Set(),
  };
}

function armExpiry(session: Session): void {
  if (session.expires) clearTimeout(session.expires);
  session.expires = setTimeout(() => {
    sessions.delete(session.id);
    session.abort?.abort();
    for (const socket of session.sockets) socket.close();
  }, TTL_MS);
  session.expires.unref();
}

function cleanUserId(value: string | undefined): string | undefined {
  if (!value?.trim()) return undefined;
  const clean = value.trim().replace(/[^\w.-]/g, "").slice(0, 64);
  return clean || undefined;
}

function cap(text: string, max: number): string {
  return text.length <= max ? text : text.slice(0, max);
}
