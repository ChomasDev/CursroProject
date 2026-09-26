/** One private stdin request per process. Keys never go into URLs, argv, or files. */
import { generateText } from "ai";
import { languageModel, type AISettings } from "./services/ai.service";
import { finishRoast, prepareTurn } from "./services/ando.service";

function send(value: unknown) { process.stdout.write(`${JSON.stringify(value)}\n`); }

async function main() {
  let raw = "";
  for await (const chunk of process.stdin) {
    raw += chunk;
    if (raw.length > 64_000) throw new Error("Prompt too long.");
  }
  const body = JSON.parse(raw) as { operation?: string; prompt?: string; user?: string; ai?: AISettings };
  const ai = body.ai;
  if (!ai || !["anthropic", "openai", "google", "openrouter"].includes(ai.provider)
    || typeof ai.apiKey !== "string" || !ai.apiKey.trim()
    || typeof ai.model !== "string" || !ai.model.trim()) throw new Error("Choose a provider, model, and API key in Settings.");
  if (body.operation === "test") {
    try {
      await generateText({ model: languageModel(ai), prompt: "Reply with OK.", maxOutputTokens: 128,
        maxRetries: 0, abortSignal: AbortSignal.timeout(20_000) });
    } catch {
      throw new Error("Connection failed. Check your API key, model, provider quota, and internet connection.");
    }
    send({ type: "done" });
    return;
  }
  if (typeof body.prompt !== "string" || !body.prompt.trim()) throw new Error("Enter a prompt first.");
  const user = typeof body.user === "string" ? body.user.slice(0, 24) : "anon";
  const prepared = prepareTurn(body.prompt.slice(0, 4000), undefined, user);
  const s = prepared.stats;
  send({ type: "stats", stats: {
    similar_count: s.similarCount, token_count: s.tokenCount, seconds_spent: s.secondsSpent,
    prompts_per_day: s.promptsPerDay, hourly_wage: s.hourlyWage, euro_per_day: s.euroPerDay,
    euro_per_month: s.euroPerMonth, leaderboard_rank: s.rank, leaderboard_total: s.totalUsers,
    people_above: s.peopleAbove, leaderboard: prepared.leaderboard, badges: prepared.badges,
  } });
  const roast = await finishRoast(prepared, undefined, ai);
  for (const [section, value] of Object.entries(roast)) {
    if (typeof value === "boolean") continue;
    for (const text of Array.isArray(value) ? value : [value]) send({ type: "phrase", section, text });
  }
  send({ type: "done" });
}

main().catch((error: unknown) => {
  send({ type: "error", message: error instanceof Error ? error.message : "Could not generate the roast." });
  process.exitCode = 1;
});
