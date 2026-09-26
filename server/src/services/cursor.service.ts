import { spawn } from "node:child_process";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { AndoError } from "../errors";

/** Runs one prompt through the user's signed-in Cursor CLI (`agent -p`), so no API key is needed. */
export async function cursorComplete(
  agentPath: string,
  model: string,
  system: string,
  user: string,
  signal?: AbortSignal,
  timeoutMs = 90_000,
): Promise<string> {
  // An empty scratch workspace keeps the agent away from the user's projects.
  const workspace = await mkdtemp(join(tmpdir(), "aiando-cursor-"));
  const args = ["-p", "--output-format", "json", "--trust", "--workspace", workspace];
  if (model.trim() && model.trim() !== "auto") args.push("--model", model.trim());
  args.push(`${system}\n\nRispondi solo con testo. Non usare strumenti, file o comandi.\n\n${user}`);
  try {
    const { code, stdout, stderr } = await run(agentPath, args, signal, timeoutMs);
    if (signal?.aborted) throw new AndoError("Turn cancelled", 409);
    if (code !== 0) throw cursorError(stderr || stdout);
    return parseResult(stdout);
  } finally {
    await rm(workspace, { recursive: true, force: true });
  }
}

export function parseResult(stdout: string): string {
  const line = stdout.trim().split("\n").reverse().find((entry) => entry.trim().startsWith("{"));
  let parsed: { is_error?: boolean; result?: unknown } | undefined;
  try { parsed = line ? JSON.parse(line) : undefined; } catch { parsed = undefined; }
  if (!parsed || parsed.is_error || typeof parsed.result !== "string" || !parsed.result.trim()) {
    throw new AndoError("Cursor returned no text. Try again.", 502);
  }
  return parsed.result;
}

export function cursorError(output: string): AndoError {
  const text = output.toLowerCase();
  if (/not (logged in|authenticated)|unauthenticated|login|sign in/.test(text)) {
    return new AndoError("Cursor is not connected. Open Ai-Ando and click Connect Cursor.", 401);
  }
  if (/rate limit|usage limit|quota|too many requests/.test(text)) {
    return new AndoError("Cursor usage limit reached. Check your Cursor plan.", 429);
  }
  if (/model/.test(text)) return new AndoError("Cursor rejected the model. Pick another one in Settings.", 400);
  return new AndoError("Cursor could not answer. Try again.", 502);
}

function run(command: string, args: string[], signal: AbortSignal | undefined, timeoutMs: number) {
  return new Promise<{ code: number | null; stdout: string; stderr: string }>((resolve, reject) => {
    const child = spawn(command, args, {
      stdio: ["ignore", "pipe", "pipe"],
      env: { ...process.env, PATH: `${dirname(command)}:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin`, NO_OPEN_BROWSER: "1" },
    });
    let stdout = "", stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    const timer = setTimeout(() => { child.kill(); reject(new AndoError("Cursor took too long. Try again.", 504)); }, timeoutMs);
    const abort = () => child.kill();
    signal?.addEventListener("abort", abort, { once: true });
    child.on("error", () => {
      clearTimeout(timer);
      reject(new AndoError("Cursor CLI not found. Open Ai-Ando and click Connect Cursor.", 500));
    });
    child.on("close", (code) => {
      clearTimeout(timer);
      signal?.removeEventListener("abort", abort);
      resolve({ code, stdout, stderr });
    });
  });
}
