import assert from "node:assert/strict";
import { test } from "node:test";
import { spawnSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

function runWorker(request: unknown) {
  const folder = mkdtempSync(path.join(tmpdir(), "aiando-worker-"));
  try {
    const result = spawnSync(process.execPath, ["dist/ai-worker.cjs"], {
      input: JSON.stringify(request), encoding: "utf8", timeout: 5000,
      env: { PATH: process.env.PATH, AIANDO_DESKTOP: "1", AIANDO_DATA_FILE: path.join(folder, "board.json"),
        SYSTEM_PROMPT_PATH: path.resolve("../prompts/ai-ando-system-prompt.md") },
    });
    assert.equal(result.error, undefined);
    return { status: result.status, raw: result.stdout,
      frames: result.stdout.trim().split("\n").map((line) => JSON.parse(line)) };
  } finally { rmSync(folder, { recursive: true, force: true }); }
}

test("bundled worker rejects incomplete settings with a readable error frame", () => {
  const result = runWorker({ prompt: "Hello", ai: { provider: "unknown", model: "test", apiKey: "test-key" } });
  assert.equal(result.status, 1);
  assert.equal(result.frames[0].type, "error");
  assert.match(result.frames[0].message, /Choose a provider/);
  assert.ok(!result.raw.includes("test-key"));
});

test("bundled worker emits full wire frames without calling a provider for a secret prompt", () => {
  const secret = "sk-this-is-a-fixture-secret-123456";
  const result = runWorker({ prompt: `Fix this ${secret}`, user: "fixture",
    ai: { provider: "anthropic", model: "test-model", apiKey: "not-a-real-api-key" } });
  assert.equal(result.status, 0);
  assert.equal(result.frames[0].type, "stats");
  assert.equal(result.frames.at(-1).type, "done");
  assert.ok(result.frames.some((frame) => frame.type === "phrase" && frame.section === "prompt_migliore"));
  assert.ok(!result.raw.includes(secret));
  assert.ok(!result.raw.includes("not-a-real-api-key"));
});
