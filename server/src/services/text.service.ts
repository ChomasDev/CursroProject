import type { Request } from "express";
import { config, wsPath } from "../config";
import { AndoError } from "../errors";
import { ingest } from "./ando.service";

export async function ingestHttp(req: Request): Promise<{ status: number; body: unknown }> {
  try {
    const result = await ingest(req.body);
    if (result.kind === "opened") {
      return {
        status: 201,
        body: { sessionId: result.sessionId, websocket: websocketUrl(req, result.sessionId) },
      };
    }
    if (result.kind === "appended") {
      return { status: 202, body: { sessionId: result.sessionId, chars: result.chars } };
    }
    return { status: 200, body: { sessionId: result.sessionId, data: result.data } };
  } catch (error) {
    if (error instanceof AndoError && error.status === 409 && error.message === "Turno annullato") {
      return { status: 409, body: { error: error.message } };
    }
    throw error;
  }
}

function websocketUrl(req: Request, sessionId: string): string {
  const host = req.get("host") ?? `localhost:${config.port}`;
  const forwarded = req.get("x-forwarded-proto");
  const secure = forwarded === "https" || req.secure;
  return `${secure ? "wss" : "ws"}://${host}${wsPath}?sessionId=${encodeURIComponent(sessionId)}`;
}
