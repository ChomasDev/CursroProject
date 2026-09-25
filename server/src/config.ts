import path from "path";
import dotenv from "dotenv";

dotenv.config({ path: path.resolve(__dirname, "../.env") });

function num(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export const wsPath = "/api/ws";

export const config = {
  port: num(process.env.PORT, 3000),
  nodeEnv: process.env.NODE_ENV ?? "development",
  anthropicApiKey: process.env.ANTHROPIC_API_KEY ?? "",
  anthropicModel: process.env.ANTHROPIC_MODEL ?? "claude-sonnet-4-6",
  perplexityApiKey: process.env.PERPLEXITY_API_KEY ?? "",
  perplexityPreset: process.env.PERPLEXITY_PRESET ?? "fast",
  hourlyWageEur: num(process.env.HOURLY_WAGE_EUR, 15.5),
  promptPath: process.env.SYSTEM_PROMPT_PATH
    ? path.resolve(process.env.SYSTEM_PROMPT_PATH)
    : "",
};
