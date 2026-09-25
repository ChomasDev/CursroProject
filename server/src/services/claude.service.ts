import { config } from "../config";
import { AndoError } from "../errors";
import { extractJson } from "./json";

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

type ClaudeResponse = {
  content?: Array<{ type?: string; text?: string }>;
  error?: { message?: string };
};

export async function writeRoast(
  system: string,
  user: string,
  signal?: AbortSignal,
): Promise<AndoRoast> {
  if (!config.anthropicApiKey) {
    throw new AndoError("Manca ANTHROPIC_API_KEY nel file server/.env", 500);
  }
  const first = await complete(system, user, signal);
  try {
    return coerceRoast(extractJson(first));
  } catch {
    const second = await complete(
      system,
      `${user}\n\nIl messaggio precedente non era il JSON richiesto. Rispondi solo con l'oggetto JSON, senza markdown.\n\nOUTPUT PRECEDENTE:\n${first.slice(0, 1500)}`,
      signal,
    );
    return coerceRoast(extractJson(second));
  }
}

async function complete(system: string, user: string, signal?: AbortSignal): Promise<string> {
  const body: Record<string, unknown> = {
    model: config.anthropicModel,
    max_tokens: 1500,
    system,
    messages: [{ role: "user", content: user }],
  };
  if (allowsTemperature(config.anthropicModel)) body.temperature = 0.9;

  let response: Response;
  try {
    response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "x-api-key": config.anthropicApiKey,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(45_000)]) : AbortSignal.timeout(45_000),
    });
  } catch (error) {
    if (error instanceof Error && error.name === "TimeoutError") {
      throw new AndoError("Claude ha impiegato troppo", 504);
    }
    if (error instanceof Error && error.name === "AbortError") {
      throw new AndoError("Turno annullato", 409);
    }
    throw new AndoError("Claude non raggiungibile", 502);
  }

  const raw = await response.text();
  if (!response.ok) {
    throw new AndoError(`Claude ${response.status}: ${raw.slice(0, 240)}`, 502);
  }
  const parsed = JSON.parse(raw) as ClaudeResponse;
  const text = (parsed.content ?? [])
    .filter((block) => block.type === "text" && block.text)
    .map((block) => block.text)
    .join("\n")
    .trim();
  if (!text) throw new AndoError(parsed.error?.message || "Claude non ha risposto", 502);
  return text;
}

function allowsTemperature(model: string): boolean {
  return !/claude-(sonnet-5|opus-5|fable-5|mythos)/.test(model);
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
