import { config } from "../config";
import { AndoError } from "../errors";
import { extractJson } from "./json";

export type Citation = {
  found: boolean;
  work: string;
  quote: string;
  note: string;
};

type AgentOutput = {
  type?: string;
  content?: Array<{ type?: string; text?: string }>;
  results?: Array<{ title?: string; url?: string }>;
};

type AgentResponse = {
  status?: string;
  error?: { message?: string } | null;
  output?: AgentOutput[];
};

export async function searchCitation(userText: string, signal?: AbortSignal): Promise<Citation> {
  if (!config.perplexityApiKey) {
    throw new AndoError("Manca PERPLEXITY_API_KEY nel file server/.env", 500);
  }

  const sample = userText.replace(/\s+/g, " ").trim().slice(0, 700);
  const response = await postAgent(
    {
      preset: config.perplexityPreset,
      max_output_tokens: 700,
      input: [
        "Cerca sul web una citazione REALE di al massimo 6 parole, da un libro, un film o una canzone,",
        "che somiglia a una frase di questo testo. Preferisci Harry Potter o un'altra opera famosa solo se l'aggancio è vero.",
        "Non inventare e non citare più di 6 parole.",
        'Rispondi solo con JSON: {"found":true|false,"work":"","quote":"","note":""}',
        "",
        "TESTO:",
        sample,
      ].join("\n"),
    },
    signal,
  );

  const text = messageText(response);
  const sources = sourceTitles(response);
  const citation = normalizeCitation(text, sources);
  console.log(
    `citation found=${citation.found} work=${citation.work || "-"} sources=${sources.length}`,
  );
  return citation;
}

async function postAgent(body: unknown, signal?: AbortSignal): Promise<AgentResponse> {
  let response: Response;
  try {
    response = await fetch("https://api.perplexity.ai/v1/agent", {
      method: "POST",
      headers: {
        authorization: `Bearer ${config.perplexityApiKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
      signal: withTimeout(signal, 40_000),
    });
  } catch (error) {
    throw networkError("Perplexity", error);
  }

  const raw = await response.text();
  if (!response.ok) {
    throw new AndoError(`Perplexity ${response.status}: ${raw.slice(0, 240)}`, 502);
  }
  const parsed = JSON.parse(raw) as AgentResponse;
  if (parsed.status === "failed") {
    throw new AndoError(parsed.error?.message || "Perplexity non ha completato la ricerca", 502);
  }
  return parsed;
}

function messageText(response: AgentResponse): string {
  const parts: string[] = [];
  for (const item of response.output ?? []) {
    if (item.type && item.type !== "message") continue;
    for (const block of item.content ?? []) {
      if (block.text) parts.push(block.text);
    }
  }
  return parts.join("\n").trim();
}

function sourceTitles(response: AgentResponse): string[] {
  const titles: string[] = [];
  for (const item of response.output ?? []) {
    if (item.type !== "search_results") continue;
    for (const result of item.results ?? []) {
      if (result.title) titles.push(result.title);
    }
  }
  return titles.slice(0, 3);
}

function normalizeCitation(text: string, sources: string[]): Citation {
  let found = false;
  let work = "";
  let quote = "";
  let note = "";
  try {
    const parsed = extractJson(text) as Record<string, unknown>;
    found = parsed.found === true;
    work = clip(asText(parsed.work), 120);
    quote = clipWords(asText(parsed.quote), 6);
    note = clip(asText(parsed.note), 240);
  } catch {
    note = clip(text, 240);
  }
  if (!work && sources[0]) work = clip(sources[0], 120);
  if (found && (!work || !quote)) found = false;
  if (!found) quote = "";
  return { found, work, quote, note };
}

function asText(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function clip(text: string, max: number): string {
  return text.length <= max ? text : text.slice(0, max).trim();
}

function clipWords(quote: string, max: number): string {
  const words = quote.replace(/^["'«»]+|["'«»]+$/g, "").trim().split(/\s+/).filter(Boolean);
  return words.slice(0, max).join(" ");
}

function withTimeout(signal: AbortSignal | undefined, ms: number): AbortSignal {
  const timeout = AbortSignal.timeout(ms);
  return signal ? AbortSignal.any([signal, timeout]) : timeout;
}

function networkError(who: string, error: unknown): AndoError {
  if (error instanceof Error && error.name === "TimeoutError") {
    return new AndoError(`${who} ha impiegato troppo`, 504);
  }
  if (error instanceof Error && error.name === "AbortError") {
    return new AndoError("Turno annullato", 409);
  }
  return new AndoError(`${who} non raggiungibile`, 502);
}
