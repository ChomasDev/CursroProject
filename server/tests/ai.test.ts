import assert from "node:assert/strict";
import { test } from "node:test";
import { generateText } from "ai";
import { languageModel, writeRoast, type AISettings } from "../src/services/ai.service";

const key = "test-key-do-not-leak";
const roast = { roast_mode: true, cloni: "Cloni", fun_fact_frase: "Fun fact", soldi_gratis: "Soldi",
  invece_potevi: ["Drink water"], classifica: "Classifica", prompt_migliore: "Better prompt", commento_prompt_migliore: "Verdict" };

for (const provider of ["anthropic", "openai", "google", "openrouter"] as const) {
  test(`${provider} routes the chosen model and key to its own endpoint`, async () => {
    const original = globalThis.fetch;
    const model = provider === "google" ? "gemini-2.5-flash" : provider === "openai" ? "gpt-4.1-mini" : "test-model";
    const ai: AISettings = { provider, model, apiKey: key };
    let called = false;
    globalThis.fetch = async (url, init) => {
      called = true;
      const endpoint = String(url);
      const headers = new Headers(init?.headers);
      const body = JSON.parse(String(init?.body));
      if (provider === "anthropic") {
        assert.ok(endpoint.startsWith("https://api.anthropic.com/"));
        assert.equal(headers.get("x-api-key"), key);
        assert.equal(body.model, model);
        return Response.json({ id: "msg_1", type: "message", role: "assistant", model, content: [{ type: "text", text: "OK" }],
          stop_reason: "end_turn", stop_sequence: null, usage: { input_tokens: 1, output_tokens: 1 } });
      }
      if (provider === "google") {
        assert.ok(endpoint.startsWith("https://generativelanguage.googleapis.com/"));
        assert.ok(endpoint.includes(model));
        assert.equal(headers.get("x-goog-api-key"), key);
        return Response.json({ candidates: [{ content: { role: "model", parts: [{ text: "OK" }] }, finishReason: "STOP" }],
          usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1, totalTokenCount: 2 } });
      }
      assert.equal(headers.get("authorization"), `Bearer ${key}`);
      assert.equal(body.model, model);
      if (provider === "openai") {
        assert.ok(endpoint.startsWith("https://api.openai.com/"));
        return Response.json({ id: "resp_1", created_at: 1, model,
          output: [{ type: "message", id: "msg_1", role: "assistant", status: "completed",
            content: [{ type: "output_text", text: "OK", annotations: [] }] }],
          usage: { input_tokens: 1, output_tokens: 1, total_tokens: 2 }, status: "completed" });
      }
      assert.ok(endpoint.startsWith("https://openrouter.ai/api/v1/"));
      return Response.json({ id: "chat_1", created: 1, model,
        choices: [{ index: 0, message: { role: "assistant", content: "OK" }, finish_reason: "stop" }],
        usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 } });
    };
    try {
      const result = await generateText({ model: languageModel(ai), prompt: "Test", maxRetries: 0 });
      assert.equal(result.text, "OK");
      assert.ok(called);
    } finally { globalThis.fetch = original; }
  });
}

test("a malformed roast is repaired once, and provider errors never expose the API key", async () => {
  const original = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ id: "msg_1", type: "message", role: "assistant", model: "test", content: [{ type: "text", text: calls === 1 ? "invalid" : JSON.stringify(roast) }],
      stop_reason: "end_turn", stop_sequence: null, usage: { input_tokens: 1, output_tokens: 1 } });
  };
  const settings: AISettings = { provider: "anthropic", model: "test", apiKey: key };
  try {
    assert.deepEqual(await writeRoast("System", "Prompt", undefined, settings), roast);
    assert.equal(calls, 2);
    globalThis.fetch = async () => Response.json({ type: "error", error: { type: "authentication_error", message: key } }, { status: 401 });
    await assert.rejects(writeRoast("System", "Prompt", undefined, settings), (error: Error) => {
      assert.match(error.message, /API key rejected/);
      assert.ok(!error.message.includes(key));
      return true;
    });
  } finally { globalThis.fetch = original; }
});
