import cors from "cors";
import express from "express";
import { router } from "./routes";

export function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ type: ["application/json", "text/json"] }));
  app.use("/api", router);

  app.use((_req, res) => {
    res.status(404).json({ error: "Not found" });
  });

  return app;
}
