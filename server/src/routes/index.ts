import { Router } from "express";
import { healthRouter } from "./health.routes";
import { textRouter } from "./text.routes";

export const router = Router();

router.use("/health", healthRouter);
router.use("/getText", textRouter);
