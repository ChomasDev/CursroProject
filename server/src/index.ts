import { createServer } from "http";
import { createApp } from "./app";
import { config, wsPath } from "./config";
import { attachWebSocket } from "./ws";

const app = createApp();
const server = createServer(app);
attachWebSocket(server);

server.listen(config.port, () => {
  console.log(`Server listening on port ${config.port}`);
  console.log(`WebSocket on ws://localhost:${config.port}${wsPath}`);
});
