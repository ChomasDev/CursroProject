import { Router } from "express";
import { logRequestBody } from "../services/text.service";

export const textRouter = Router();

textRouter.post("/", (req, res) => {
  logRequestBody(req.body);
  res.status(204).send();
});
