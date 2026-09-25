import fs from "fs";
import path from "path";
import { config } from "../config";
import type { Citation } from "./perplexity.service";
import type { TurnStats } from "./stats.service";

let cached: string | undefined;

export function systemPrompt(): string {
  if (cached) return cached;
  const raw = fs.readFileSync(promptFile(), "utf8");
  const start = raw.indexOf("## SYSTEM PROMPT");
  const end = raw.indexOf("## Note per il backend");
  const body = (start >= 0 ? raw.slice(start, end > start ? end : undefined) : raw).trim();
  cached = `${body}

ECCEZIONE BACKEND:
CITAZIONE_PERPLEXITY è una ricerca vera. Se found è true, fun_fact_frase deve usare il titolo esatto di work e la quote (già al massimo 6 parole), con il tono roast. Non sostituirla con una citazione inventata e non allungare la quote. Se found è false, il fun fact resta palesemente ironico e inventato.`;
  return cached;
}

export function userPrompt(
  userText: string,
  assistantText: string,
  stats: TurnStats,
  citation: Citation,
): string {
  const ai = assistantText.trim()
    ? clipTail(assistantText.trim(), 6000)
    : "(l'AI non ha ancora scritto niente)";

  return `PROMPT_UTENTE: ${clip(userText.trim(), 4000)}
TOKEN_PROMPT: ${stats.tokenCount}
PERSONE_CON_PROMPT_SIMILE: ${stats.similarCount}
SECONDI_PERSI_SU_QUESTO_PROMPT: ${stats.secondsSpent}
PROMPT_AL_GIORNO_STIMATI: ${stats.promptsPerDay}
STIPENDIO_ORARIO_MEDIO_EUR: ${stats.hourlyWage.toFixed(2)}
EURO_AL_GIORNO_A_GRATIS: ${stats.euroPerDay.toFixed(2)}
EURO_AL_MESE_A_GRATIS: ${stats.euroPerMonth.toFixed(2)}
POSIZIONE_CLASSIFICA: ${stats.rank}
UTENTI_TOTALI: ${stats.totalUsers}
PERSONE_CHE_AI_ANDO_PIU_DI_TE: ${stats.peopleAbove}

CITAZIONE_PERPLEXITY: ${JSON.stringify(citation)}

TESTO_AI_CHE_STA_SCRIVENDO:
${ai}

Rispondi solo con il JSON dello schema. Usa esattamente questi numeri, senza cambiarli.
Se CITAZIONE_PERPLEXITY.found è true, fun_fact_frase deve contenere work e quote così come sono.`;
}

function promptFile(): string {
  if (config.promptPath) return config.promptPath;
  const candidates = [
    path.resolve(process.cwd(), "prompts/ai-ando-system-prompt.md"),
    path.resolve(process.cwd(), "../prompts/ai-ando-system-prompt.md"),
    path.resolve(__dirname, "../../../prompts/ai-ando-system-prompt.md"),
    path.resolve(__dirname, "../../prompts/ai-ando-system-prompt.md"),
  ];
  const found = candidates.find((file) => fs.existsSync(file));
  if (!found) throw new Error("prompts/ai-ando-system-prompt.md non trovato");
  return found;
}

function clip(text: string, max: number): string {
  if (text.length <= max) return text;
  return `${text.slice(0, max)}\n…[troncato]`;
}

function clipTail(text: string, max: number): string {
  if (text.length <= max) return text;
  return `…[troncato]\n${text.slice(-max)}`;
}
