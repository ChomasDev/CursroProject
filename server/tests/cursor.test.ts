import assert from "node:assert/strict";
import { chmod, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { cursorComplete } from "../src/services/cursor.service";
import { AndoError } from "../src/errors";

async function fakeAgent(script: string) {
  const dir = await mkdtemp(join(tmpdir(), "fake-agent-"));
  const path = join(dir, "agent");
  await writeFile(path, `#!/bin/sh\nprintf '%s\\n' "$@" > "${dir}/args"\n${script}\n`);
  await chmod(path, 0o755);
  return { path, args: async () => (await readFile(join(dir, "args"), "utf8")).split("\n") };
}

test("cursor provider runs the CLI headless in a scratch workspace and returns its text", async () => {
  const agent = await fakeAgent(`echo '{"type":"result","subtype":"success","is_error":false,"result":"OK roast"}'`);
  const text = await cursorComplete(agent.path, "sonnet-4", "SYSTEM", "USER");
  assert.equal(text, "OK roast");
  const args = await agent.args();
  assert.ok(args.includes("-p"));
  assert.ok(args.includes("--trust"));
  assert.ok(!args.includes("--force"));
  assert.equal(args[args.indexOf("--model") + 1], "sonnet-4");
  assert.ok(args[args.indexOf("--workspace") + 1].includes("aiando-cursor-"));
  assert.ok(args.some((arg) => arg.includes("SYSTEM")));
});

test("auto model lets Cursor pick", async () => {
  const agent = await fakeAgent(`echo '{"type":"result","is_error":false,"result":"OK"}'`);
  await cursorComplete(agent.path, "auto", "S", "U");
  assert.ok(!(await agent.args()).includes("--model"));
});

test("a signed-out CLI asks the user to connect Cursor", async () => {
  const agent = await fakeAgent(`echo 'Error: Not authenticated. Run agent login' >&2; exit 1`);
  await assert.rejects(cursorComplete(agent.path, "auto", "S", "U"),
    (error: unknown) => error instanceof AndoError && error.status === 401);
});

test("a missing CLI reports a clear error", async () => {
  await assert.rejects(cursorComplete("/nonexistent/agent", "auto", "S", "U"), /Connect Cursor/);
});
