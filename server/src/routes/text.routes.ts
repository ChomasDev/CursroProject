import { Router } from "express";
import { AndoError } from "../errors";
import { ingestHttp } from "../services/text.service";

export const textRouter = Router();

textRouter.post("/", async (req, res) => {
  try {
    const result = await ingestHttp(req);
    res.status(result.status).json(result.body);
  } catch (error) {
    const status = error instanceof AndoError ? error.status : 500;
    const message = error instanceof Error ? error.message : "Errore";
    res.status(status).json({ error: message });
  }
});
