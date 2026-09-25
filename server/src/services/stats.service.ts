import fs from "fs";
import path from "path";
import { randomInt } from "crypto";
import { config } from "../config";

const DAY_MS = 24 * 60 * 60 * 1000;
const FILE = path.resolve(__dirname, "../../data/leaderboard.json");

type Entry = { tokens: number; prompts: number[] };
type Board = Record<string, Entry>;

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

export function recordTurn(userId: string, userText: string, startedAt: number): TurnStats {
  const now = Date.now();
  const tokenCount = Math.max(1, Math.ceil(userText.length / 4));
  const entry = board[userId] ?? { tokens: 0, prompts: [] };
  entry.tokens += tokenCount;
  entry.prompts = entry.prompts.filter((stamp) => now - stamp < DAY_MS);
  entry.prompts.push(now);
  board[userId] = entry;
  save();

  const totals = Object.values(board).map((item) => item.tokens);
  const peopleAbove = totals.filter((tokens) => tokens > entry.tokens).length;
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
    totalUsers: totals.length,
    peopleAbove,
  };
}

function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

function load(): Board {
  try {
    const parsed: unknown = JSON.parse(fs.readFileSync(FILE, "utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return {};
    return parsed as Board;
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
