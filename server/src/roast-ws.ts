import { WebSocket, WebSocketServer, type RawData } from "ws";
import { AndoError } from "./errors";
import { finishRoast, prepareTurn } from "./services/ando.service";
import type { AndoRoast } from "./services/claude.service";
import type { LeaderboardRow, TurnStats } from "./services/stats.service";

const TEXT_SECTIONS = [
  "cloni",
  "fun_fact_frase",
  "soldi_gratis",
  "classifica",
  "prompt_migliore",
  "commento_prompt_migliore",
] as const;

type TextSection = (typeof TEXT_SECTIONS)[number];

export function attachRoastSocket(): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true, maxPayload: 1_000_000 });
  wss.on("connection", (socket) => {
    const abort = new AbortController();
    socket.on("close", () => abort.abort());
    socket.once("message", (data) => {
      void handle(socket, data, abort);
    });
  });
  return wss;
}

async function handle(socket: WebSocket, data: RawData, abort: AbortController): Promise<void> {
  const ping = setInterval(() => send(socket, { type: "ping" }), 4000);
  ping.unref();
  try {
    const request = parseRequest(rawText(data));
    const prepared = prepareTurn(request.prompt, request.tokenCount, request.userId);
    send(socket, statsFrame(prepared.stats, prepared.leaderboard, prepared.badges));
    const roast = await finishRoast(prepared, abort.signal);
    await streamRoast(socket, roast, abort.signal);
    send(socket, { type: "done" });
    console.log(`roast stream done tokens=${prepared.stats.tokenCount} rank=${prepared.stats.rank}`);
    setTimeout(() => socket.close(), 1500).unref();
  } catch (error) {
    if (abort.signal.aborted || socket.readyState !== WebSocket.OPEN) return;
    const message = error instanceof Error ? error.message : "Errore";
    send(socket, { type: "error", message });
  } finally {
    clearInterval(ping);
  }
}

function parseRequest(raw: string): { prompt: string; tokenCount?: number; userId: string } {
  let body: unknown;
  try {
    body = JSON.parse(raw);
  } catch {
    throw new AndoError("Richiesta non valida", 400);
  }
  if (!body || typeof body !== "object") throw new AndoError("Richiesta non valida", 400);
  const record = body as Record<string, unknown>;
  const prompt = typeof record.prompt === "string" ? record.prompt.trim() : "";
  if (!prompt) throw new AndoError("Manca il prompt", 400);
  const tokenCount = typeof record.token_count === "number" ? record.token_count : undefined;
  return { prompt, tokenCount, userId: cleanUser(record.user) };
}

function cleanUser(value: unknown): string {
  const raw = typeof value === "string" ? value : "";
  const name = raw.replace(/\s+/g, " ").trim().slice(0, 24);
  return name || "anon";
}

function statsFrame(stats: TurnStats, leaderboard: LeaderboardRow[], badges: string[]) {
  return {
    type: "stats",
    stats: {
      similar_count: stats.similarCount,
      token_count: stats.tokenCount,
      seconds_spent: stats.secondsSpent,
      prompts_per_day: stats.promptsPerDay,
      hourly_wage: stats.hourlyWage,
      euro_per_day: stats.euroPerDay,
      euro_per_month: stats.euroPerMonth,
      leaderboard_rank: stats.rank,
      leaderboard_total: stats.totalUsers,
      people_above: stats.peopleAbove,
      leaderboard,
      badges,
    },
  };
}

async function streamRoast(socket: WebSocket, roast: AndoRoast, signal: AbortSignal): Promise<void> {
  await streamWords(socket, "cloni", roast.cloni, signal);
  await streamWords(socket, "fun_fact_frase", roast.fun_fact_frase, signal);
  await streamWords(socket, "soldi_gratis", roast.soldi_gratis, signal);
  await streamLines(socket, "invece_potevi", roast.invece_potevi, signal);
  await streamWords(socket, "classifica", roast.classifica, signal);
  await streamWords(socket, "prompt_migliore", roast.prompt_migliore, signal);
  await streamWords(socket, "commento_prompt_migliore", roast.commento_prompt_migliore, signal);
}

async function streamLines(
  socket: WebSocket,
  section: "invece_potevi",
  lines: string[],
  signal: AbortSignal,
): Promise<void> {
  for (const line of lines) {
    send(socket, { type: "phrase", section, text: line });
    await pause(60, signal);
  }
}

async function streamWords(
  socket: WebSocket,
  section: TextSection,
  text: string,
  signal: AbortSignal,
): Promise<void> {
  const words = text.trim().split(/\s+/).filter(Boolean);
  for (let index = 0; index < words.length; index += 1) {
    const piece = index === 0 ? words[index] : ` ${words[index]}`;
    send(socket, { type: "delta", section, text: piece });
    await pause(16, signal);
  }
}

function pause(ms: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.reject(new AndoError("Turno annullato", 409));
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    const onAbort = () => {
      clearTimeout(timer);
      reject(new AndoError("Turno annullato", 409));
    };
    signal.addEventListener("abort", onAbort, { once: true });
  });
}

function rawText(data: RawData): string {
  if (Array.isArray(data)) return Buffer.concat(data).toString("utf8");
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
  return data.toString("utf8");
}

function send(socket: WebSocket, payload: unknown): void {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}
