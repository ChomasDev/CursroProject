import type { WebSocket } from "ws";
import { AndoError } from "../errors";
import { parseBody, sessionIdOf, type Incoming } from "../protocol";
import { hasSecret } from "../secrets";
import {
  appendAssistant,
  broadcast,
  requireSession,
  startTurn,
  type Session,
} from "../sessions";
import type { AndoRoast } from "./claude.service";
import { writeRoast } from "./claude.service";
import { searchCitation } from "./perplexity.service";
import { systemPrompt, userPrompt } from "./prompt.service";
import { recordTurn, type TurnStats } from "./stats.service";

export type IngestResult =
  | { kind: "opened"; sessionId: string }
  | { kind: "appended"; sessionId: string; chars: number }
  | { kind: "roast"; sessionId: string; data: AndoRoast };

export async function ingest(body: unknown): Promise<IngestResult> {
  const existingId = sessionIdOf(body);
  const existing = existingId ? requireSession(existingId) : undefined;
  const incoming = parseBody(body, Boolean(existing));
  return applyIncoming(existing, incoming);
}

export async function applyIncoming(
  existing: Session | undefined,
  incoming: Incoming,
  socket?: WebSocket,
): Promise<IngestResult> {
  if (incoming.type === "user") {
    const session = startTurn({
      session: existing,
      userText: incoming.text,
      userId: incoming.userId,
      socket,
    });
    return { kind: "opened", sessionId: session.id };
  }
  if (!existing) throw new AndoError("Il primo messaggio deve essere il testo dell'utente", 400);
  if (incoming.type === "assistant") {
    const chars = appendAssistant(existing, incoming.text);
    return { kind: "appended", sessionId: existing.id, chars };
  }
  if (incoming.text) appendAssistant(existing, incoming.text);
  const data = await runTurn(existing);
  return { kind: "roast", sessionId: existing.id, data };
}

export function runTurn(session: Session): Promise<AndoRoast> {
  if (session.finished && session.roast) return Promise.resolve(session.roast);
  if (session.job) return session.job;

  const generation = session.generation;
  const signal = session.abort?.signal;
  const job = produce(session, generation, signal).then(
    (roast) => {
      if (session.generation === generation) {
        session.finished = true;
        session.roast = roast;
        session.job = undefined;
        broadcast(session, { type: "roast", data: roast });
        console.log(`roast ready ${session.id} mode=${roast.roast_mode}`);
      }
      return roast;
    },
    (error: unknown) => {
      if (session.job === job) session.job = undefined;
      const normalized = normalize(error);
      if (session.generation === generation) {
        normalized.notified = true;
        broadcast(session, { type: "error", message: normalized.message });
      }
      throw normalized;
    },
  );
  session.job = job;
  return job;
}

async function produce(
  session: Session,
  generation: number,
  signal?: AbortSignal,
): Promise<AndoRoast> {
  const stats = draftStats(session, generation);
  if (hasSecret(`${session.userText}\n${session.assistantText}`)) {
    return secretRoast(stats);
  }
  systemPrompt();
  if (session.generation === generation) {
    broadcast(session, { type: "status", step: "citation" });
  }
  const citation = await searchCitation(session.userText, signal);
  if (session.generation === generation) {
    broadcast(session, { type: "status", step: "roast" });
  }
  return writeRoast(
    systemPrompt(),
    userPrompt(session.userText, session.assistantText, stats, citation),
    signal,
  );
}

function draftStats(session: Session, generation: number): TurnStats {
  if (session.draft && session.draftGeneration === generation) return session.draft;
  const stats = recordTurn(session.userId, session.userText, session.startedAt);
  session.draft = stats;
  session.draftGeneration = generation;
  return stats;
}

function secretRoast(stats: TurnStats): AndoRoast {
  const people = new Intl.NumberFormat("it-IT").format(stats.similarCount);
  const euroDay = money(stats.euroPerDay);
  const euroMonth = money(stats.euroPerMonth);
  const rankLine =
    stats.rank === 1
      ? `Sei ${stats.rank}° su ${stats.totalUsers} e stai vincendo l'Ai-Ando nel modo peggiore: incollando segreti.`
      : `Sei ${stats.rank}° su ${stats.totalUsers}, ci sono ${stats.peopleAbove} persone che stanno Ai-Ando più di te. Nessuna doveva vedere quella chiave.`;
  return {
    roast_mode: true,
    cloni: `Bro hai incollato una chiave o una password. Non la ripeto e non la mando a nessuno. Altre ${people} persone fanno disastri simili.`,
    fun_fact_frase:
      "Fun fact: una API key nel prompt non è una citazione di Harry Potter, è un incidente. Toglila e riprova.",
    soldi_gratis: `Bhe ipotizziamo ${stats.promptsPerDay} prompt così al giorno: sono ${euroDay}€ al giorno e ${euroMonth}€ al mese. Il tuo capo ringrazia, il leak pure.`,
    invece_potevi: [
      "Mettere la chiave nel .env, non nel prompt",
      "Revocare quella chiave, tipo ora",
      "Bere un sorso d'acqua e respirare",
    ],
    classifica: rankLine,
    prompt_migliore:
      "Rimuovi chiavi, password e dati personali. Poi riscrivi il prompt con obiettivo, file e formato dell'output.",
    commento_prompt_migliore: "Bhe coglione avresti potuto non incollare il segreto. Rifallo pulito.",
  };
}

function money(value: number): string {
  return new Intl.NumberFormat("it-IT", {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

function normalize(error: unknown): AndoError {
  if (error instanceof AndoError) return error;
  if (error instanceof Error && error.name === "AbortError") {
    return new AndoError("Turno annullato", 409);
  }
  if (error instanceof Error && error.message) return new AndoError(error.message, 500);
  return new AndoError("Errore", 500);
}
