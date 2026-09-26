import { generateText, APICallError } from "ai";
import { createAnthropic } from "@ai-sdk/anthropic";
import { createOpenAI } from "@ai-sdk/openai";
import { createGoogleGenerativeAI } from "@ai-sdk/google";
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { config } from "../config";
import { AndoError } from "../errors";
import { extractJson } from "./json";
import { cursorComplete } from "./cursor.service";

export type AndoRoast = {
  roast_mode: boolean;
  cloni: string;
  fun_fact_frase: string;
  soldi_gratis: string;
  invece_potevi: string[];
  classifica: string;
  prompt_migliore: string;
  commento_prompt_migliore: string;
};

const FIELDS = [
  "roast_mode",
  "cloni",
  "fun_fact_frase",
  "soldi_gratis",
  "invece_potevi",
  "classifica",
  "prompt_migliore",
  "commento_prompt_migliore",
] as const;

export type AISettings = {
  provider: "cursor" | "anthropic" | "openai" | "google" | "openrouter";
  model: string;
  apiKey: string;
  /** Cursor CLI binary; the Cursor provider uses the user's Cursor login instead of an API key. */
  agentPath?: string;
};

export function defaultAISettings(): AISettings {
  return { provider: "anthropic", model: config.anthropicModel, apiKey: config.anthropicApiKey };
}

export async function writeRoast(
  system: string,
  user: string,
  signal?: AbortSignal,
  settings: AISettings = defaultAISettings(),
): Promise<AndoRoast> {
  if (settings.provider !== "cursor" && !settings.apiKey.trim()) {
    throw new AndoError("Add your API key in Settings.", 500);
  }
  const first = await complete(system, user, settings, signal);
  try {
    return coerceRoast(extractJson(first));
  } catch {
    const second = await complete(
      system,
      `${user}\n\nIl messaggio precedente non era il JSON richiesto. Rispondi solo con l'oggetto JSON, senza markdown.\n\nOUTPUT PRECEDENTE:\n${first.slice(0, 1500)}`,
      settings,
      signal,
    );
    return coerceRoast(extractJson(second));
  }
}

export function languageModel(settings: AISettings) {
  switch (settings.provider) {
    case "anthropic": return createAnthropic({ apiKey: settings.apiKey })(settings.model);
    case "openai": return createOpenAI({ apiKey: settings.apiKey })(settings.model);
    case "google": return createGoogleGenerativeAI({ apiKey: settings.apiKey })(settings.model);
    case "openrouter": return createOpenAICompatible({
      name: "openrouter", baseURL: "https://openrouter.ai/api/v1", apiKey: settings.apiKey,
    })(settings.model);
    default: throw new AndoError("Choose a supported provider in Settings.", 400);
  }
}

async function complete(system: string, user: string, settings: AISettings, signal?: AbortSignal): Promise<string> {
  if (settings.provider === "cursor") {
    if (!settings.agentPath) throw new AndoError("Open Ai-Ando and click Connect Cursor.", 500);
    return cursorComplete(settings.agentPath, settings.model, system, user, signal);
  }
  try {
    const { text } = await generateText({
      model: languageModel(settings),
      system,
      prompt: user,
      maxOutputTokens: 2500,
      maxRetries: 0,
      abortSignal: signal ? AbortSignal.any([signal, AbortSignal.timeout(45_000)]) : AbortSignal.timeout(45_000),
    });
    if (!text.trim()) throw new AndoError("The model returned no text. Try another model.", 502);
    return text;
  } catch (error) {
    if (error instanceof AndoError) throw error;
    if (signal?.aborted) throw new AndoError("Turn cancelled", 409);
    if (APICallError.isInstance(error)) {
      if (error.statusCode === 401 || error.statusCode === 403) throw new AndoError("API key rejected. Check your key in Settings.", 401);
      if (error.statusCode === 429) throw new AndoError("Provider rate limit or quota reached. Check your provider account.", 429);
      throw new AndoError(`Provider request failed (${error.statusCode ?? "network"}). Check your model and provider in Settings.`, 502);
    }
    throw new AndoError("Could not reach the model. Check your connection and Settings.", 502);
  }
}

function coerceRoast(value: unknown): AndoRoast {
  if (!value || typeof value !== "object") throw new AndoError("JSON del roast non valido", 502);
  const record = value as Record<string, unknown>;
  for (const field of FIELDS) {
    if (!(field in record)) throw new AndoError(`Manca il campo ${field}`, 502);
  }
  if (typeof record.roast_mode !== "boolean") throw new AndoError("roast_mode non è boolean", 502);
  const lines = record.invece_potevi;
  if (!Array.isArray(lines) || lines.some((line) => typeof line !== "string")) {
    throw new AndoError("invece_potevi non è una lista di frasi", 502);
  }
  const invece = lines.map((line) => line.trim()).filter(Boolean);
  if (invece.length === 0) throw new AndoError("invece_potevi è vuota", 502);
  return {
    roast_mode: record.roast_mode,
    cloni: needText(record.cloni, "cloni"),
    fun_fact_frase: needText(record.fun_fact_frase, "fun_fact_frase"),
    soldi_gratis: needText(record.soldi_gratis, "soldi_gratis"),
    invece_potevi: invece,
    classifica: needText(record.classifica, "classifica"),
    prompt_migliore: needText(record.prompt_migliore, "prompt_migliore"),
    commento_prompt_migliore: needText(record.commento_prompt_migliore, "commento_prompt_migliore"),
  };
}

function needText(value: unknown, field: string): string {
  if (typeof value !== "string" || !value.trim()) {
    throw new AndoError(`Campo ${field} vuoto`, 502);
  }
  return value.trim();
}
