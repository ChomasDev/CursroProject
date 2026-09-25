import { WebSocket, WebSocketServer, type RawData } from "ws";
import { AndoError } from "./errors";
import { parseIncoming } from "./protocol";
import { getSession, snapshot, type Session } from "./sessions";
import { applyIncoming } from "./services/ando.service";

export function attachWebSocket(): WebSocketServer {
  const wss = new WebSocketServer({ noServer: true, maxPayload: 2_000_000 });
  wss.on("connection", (socket, request) => {
    const sessionId = new URL(request.url ?? "/", "http://localhost").searchParams.get("sessionId");
    let session = sessionId ? getSession(sessionId) : undefined;
    if (sessionId && !session) {
      send(socket, { type: "error", message: "Sessione sconosciuta" });
      socket.close();
      return;
    }
    if (session) {
      session.sockets.add(socket);
      send(socket, snapshot(session));
    }

    let chain = Promise.resolve();
    socket.on("message", (data) => {
      chain = chain.then(() =>
        onMessage(socket, () => session, (next) => {
          session = next;
        }, data),
      );
    });
    socket.on("close", () => {
      session?.sockets.delete(socket);
    });
  });
  return wss;
}

async function onMessage(
  socket: WebSocket,
  current: () => Session | undefined,
  setSession: (session: Session) => void,
  data: RawData,
): Promise<void> {
  const existing = current();
  try {
    const incoming = parseIncoming(rawText(data), Boolean(existing));
    const result = await applyIncoming(existing, incoming, socket);
    if (result.kind === "opened") {
      const session = getSession(result.sessionId);
      if (session) setSession(session);
    }
  } catch (error) {
    if (
      error instanceof AndoError &&
      (error.notified || error.message === "Turno annullato")
    ) {
      return;
    }
    const message = error instanceof Error ? error.message : "Errore";
    send(socket, { type: "error", message });
  }
}

function rawText(data: RawData): string {
  if (Array.isArray(data)) return Buffer.concat(data).toString("utf8");
  if (data instanceof ArrayBuffer) return Buffer.from(data).toString("utf8");
  return data.toString("utf8");
}

function send(socket: WebSocket, payload: unknown): void {
  if (socket.readyState === WebSocket.OPEN) socket.send(JSON.stringify(payload));
}
