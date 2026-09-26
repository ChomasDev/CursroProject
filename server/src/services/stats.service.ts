import fs from "fs";
import path from "path";
import { randomInt } from "crypto";
import { config } from "../config";

const DAY_MS = 24 * 60 * 60 * 1000;
const FILE = process.env.AIANDO_DATA_FILE || path.resolve(__dirname, "../../data/leaderboard.json");

type Entry = { tokens: number; prompts: number[]; lastTokens: number };
type Board = Record<string, Entry>;

const BOTS: { name: string; tokens: number }[] = [
  { name: "xX_vibecoder_Xx", tokens: 900_271 },
  { name: "giulia.prompta", tokens: 128_440 },
  { name: "bro_del_ctrl_c", tokens: 42_018 },
  { name: "nonnacursor", tokens: 7_777 },
];

export type TurnStats = {
  tokenCount: number;
  similarCount: number;
  secondsSpent: number;
  promptsPerDay: number;
  hourlyWage: number;
  euroPerDay: number;
  euroPerMonth: number;
  rank: number;
  totalUsers: number;
  peopleAbove: number;
};

let board: Board = load();

export type LeaderboardRow = { name: string; tokens: number; is_me: boolean };

export function recordTurn(
  userId: string,
  userText: string,
  startedAt: number,
  givenTokens?: number,
): TurnStats {
  const now = Date.now();
  const tokenCount =
    givenTokens && givenTokens > 0
      ? Math.round(givenTokens)
      : Math.max(1, Math.ceil(userText.length / 4));
  const entry = board[userId] ?? { tokens: 0, prompts: [], lastTokens: 0 };
  entry.tokens += tokenCount;
  entry.lastTokens = tokenCount;
  entry.prompts = entry.prompts.filter((stamp) => now - stamp < DAY_MS);
  entry.prompts.push(now);
  board[userId] = entry;
  save();

  const rows = standings(userId);
  const mine = rows.find((row) => row.isMe);
  const peopleAbove = rows.filter((row) => row.tokens > (mine?.tokens ?? entry.tokens)).length;
  const elapsed = Math.min(600, Math.max(1, Math.round((now - startedAt) / 1000)));
  const typed = Math.min(180, Math.max(1, Math.round(userText.length / 8)));
  const secondsSpent = Math.max(elapsed, typed);
  const paced = Math.min(80, Math.max(12, Math.round(2400 / secondsSpent)));
  const promptsPerDay = Math.max(entry.prompts.length, paced);
  const euroPerDay = round2((promptsPerDay * secondsSpent * config.hourlyWageEur) / 3600);

  return {
    tokenCount,
    similarCount: randomInt(1, 5_342_535),
    secondsSpent,
    promptsPerDay,
    hourlyWage: round2(config.hourlyWageEur),
    euroPerDay,
    euroPerMonth: round2(euroPerDay * 22),
    rank: peopleAbove + 1,
    totalUsers: rows.length,
    peopleAbove,
  };
}

export function leaderboardFor(userId: string): LeaderboardRow[] {
  return standings(userId)
    .slice(0, 8)
    .map((row) => ({ name: row.name, tokens: row.tokens, is_me: row.isMe }));
}

export function badgesFor(userId: string, prompt: string, tokenCount: number): string[] {
  const badges: string[] = [];
  if (/\b(per favore|please|grazie)\b/i.test(prompt)) {
    badges.push("ha detto per favore all'AI");
  }
  const recent = (board[userId]?.prompts ?? []).filter((stamp) => Date.now() - stamp < 60_000);
  if (recent.length >= 3) badges.push("3 prompt in 60s");
  const others = Object.entries(board)
    .filter(([id, item]) => id !== userId && item.lastTokens > 0)
    .map(([, item]) => item.lastTokens);
  if (others.length > 0 && tokenCount < Math.min(...others)) {
    badges.push("prompt più corto della sala");
  } else if (others.length === 0 && tokenCount <= 8) {
    badges.push("prompt cortissimo");
  }
  return badges;
}

function standings(userId: string): { name: string; tokens: number; isMe: boolean }[] {
  const rows = Object.entries(board).map(([id, entry]) => ({
    name: id,
    tokens: entry.tokens,
    isMe: id === userId,
  }));
  const taken = new Set(rows.map((row) => row.name));
  for (const bot of BOTS) {
    if (!taken.has(bot.name)) rows.push({ name: bot.name, tokens: bot.tokens, isMe: false });
  }
  return rows.sort((a, b) => b.tokens - a.tokens || a.name.localeCompare(b.name));
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function load(): Board {
  try {
    const parsed: unknown = JSON.parse(fs.readFileSync(FILE, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    const loaded: Board = {};
    for (const [id, value] of Object.entries(parsed as Record<string, unknown>)) {
      if (!value || typeof value !== "object") continue;
      const row = value as { tokens?: unknown; prompts?: unknown; lastTokens?: unknown };
      loaded[id] = {
        tokens: typeof row.tokens === "number" ? row.tokens : 0,
        prompts: Array.isArray(row.prompts) ? row.prompts.filter((n): n is number => typeof n === "number") : [],
        lastTokens: typeof row.lastTokens === "number" ? row.lastTokens : 0,
      };
    }
    return loaded;
  } catch {
    return {};
  }
}

function save(): void {
  try {
    fs.mkdirSync(path.dirname(FILE), { recursive: true });
    fs.writeFileSync(FILE, JSON.stringify(board));
  } catch (error) {
    console.error("leaderboard save failed", error);
  }
}
