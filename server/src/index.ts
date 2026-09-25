import { createServer } from "http";
import type { WebSocketServer } from "ws";
import { createApp } from "./app";
import { config, roastPath, wsPath } from "./config";
import { attachRoastSocket } from "./roast-ws";
import { attachWebSocket } from "./ws";

const app = createApp();
const server = createServer(app);
const apiSocket = attachWebSocket();
const roastSocket = attachRoastSocket();

server.on("upgrade", (request, socket, head) => {
  const pathname = new URL(request.url ?? "/", "http://localhost").pathname;
  const target = socketFor(pathname);
  if (!target) {
    socket.destroy();
    return;
  }
  target.handleUpgrade(request, socket, head, (ws) => {
    target.emit("connection", ws, request);
  });
});

function socketFor(pathname: string): WebSocketServer | undefined {
  if (pathname === wsPath) return apiSocket;
  if (pathname === roastPath) return roastSocket;
  return undefined;
}

server.listen(config.port, () => {
  console.log(`Server listening on port ${config.port}`);
  console.log(`WebSocket on ws://localhost:${config.port}${wsPath}`);
  console.log(`Roast socket on ws://localhost:${config.port}${roastPath}`);
});
