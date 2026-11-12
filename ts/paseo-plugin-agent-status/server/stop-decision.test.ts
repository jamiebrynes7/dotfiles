import assert from "node:assert/strict";
import { test } from "node:test";
import { BLOCK_REASON, runStopHook, statusSetSinceLastPrompt } from "./stop-decision.ts";

// Shapes as Claude Code writes them to its JSONL transcript.
const prompt = (text: string) => ({ type: "user", message: { role: "user", content: [{ type: "text", text }] } });
const stringPrompt = (text: string) => ({ type: "user", message: { role: "user", content: text } });
const toolResult = () => ({
  type: "user",
  message: { role: "user", content: [{ type: "tool_result", tool_use_id: "toolu_1", content: "ok" }] },
});
const toolUse = (name: string, extra: Record<string, unknown> = {}) => ({
  type: "assistant",
  message: { role: "assistant", content: [{ type: "tool_use", id: "toolu_1", name, input: {} }] },
  ...extra,
});
const reply = (text: string) => ({ type: "assistant", message: { role: "assistant", content: [{ type: "text", text }] } });
const jsonl = (...entries: unknown[]) => entries.map((entry) => JSON.stringify(entry)).join("\n") + "\n";

const SET_STATUS = "mcp__paseo__set_status";

test("a status set after the latest prompt counts", () => {
  assert.ok(statusSetSinceLastPrompt(jsonl(prompt("fix it"), toolUse("Bash"), toolResult(), toolUse(SET_STATUS), toolResult(), reply("done"))));
});

test("a status set only before the latest prompt does not count", () => {
  assert.ok(!statusSetSinceLastPrompt(jsonl(prompt("fix it"), toolUse(SET_STATUS), toolResult(), stringPrompt("thanks"), reply("np"))));
});

test("no status set at all does not count", () => {
  assert.ok(!statusSetSinceLastPrompt(jsonl(prompt("fix it"), toolUse("Bash"), toolResult(), reply("done"))));
});

test("tool results, meta entries and subagent entries don't start a new turn", () => {
  const meta = { ...prompt("<command-name>/clear</command-name>"), isMeta: true };
  const subagentPrompt = { ...prompt("subagent task"), isSidechain: true };
  assert.ok(statusSetSinceLastPrompt(jsonl(prompt("go"), toolUse(SET_STATUS), toolResult(), meta, subagentPrompt, toolResult(), reply("done"))));
});

test("a subagent's set_status call does not count for the main agent", () => {
  assert.ok(!statusSetSinceLastPrompt(jsonl(prompt("go"), toolUse(SET_STATUS, { isSidechain: true }), reply("done"))));
});

test("a torn last line is skipped", () => {
  assert.ok(statusSetSinceLastPrompt(jsonl(prompt("go"), toolUse(SET_STATUS)) + '{"type":"assis'));
});

function harness(overrides: { env?: Record<string, string>; stdin?: string; transcript?: string | Error }) {
  const out: string[] = [];
  const err: string[] = [];
  const io = {
    env: overrides.env ?? { PASEO_STATUS: "1" },
    stdin: overrides.stdin ?? JSON.stringify({ transcript_path: "/t.jsonl", stop_hook_active: false }),
    readTranscript: async () => {
      const transcript = overrides.transcript ?? jsonl(prompt("go"), reply("done"));
      if (transcript instanceof Error) throw transcript;
      return transcript;
    },
    writeStdout: (text: string) => void out.push(text),
    writeStderr: (text: string) => void err.push(text),
  };
  return { io, out, err };
}

test("blocks a turn that ended without a status update", async () => {
  const { io, out, err } = harness({});
  await runStopHook(io);
  assert.deepEqual(JSON.parse(out.join("")), { decision: "block", reason: BLOCK_REASON });
  assert.deepEqual(err, []);
});

test("allows a turn that updated its status", async () => {
  const { io, out } = harness({ transcript: jsonl(prompt("go"), toolUse(SET_STATUS), reply("done")) });
  await runStopHook(io);
  assert.deepEqual(out, []);
});

test("does nothing outside a Paseo agent with the plugin", async () => {
  const { io, out, err } = harness({ env: {} });
  await runStopHook(io);
  assert.deepEqual([out, err], [[], []]);
});

test("allows the stop when Claude is already continuing because of a stop hook", async () => {
  const { io, out } = harness({ stdin: JSON.stringify({ transcript_path: "/t.jsonl", stop_hook_active: true }) });
  await runStopHook(io);
  assert.deepEqual(out, []);
});

test("fails open on an unreadable transcript and says so on stderr", async () => {
  const { io, out, err } = harness({ transcript: new Error("ENOENT: no such file") });
  await runStopHook(io);
  assert.deepEqual(out, []);
  assert.match(err.join(""), /ENOENT: no such file; allowing the stop/);
});

test("fails open on malformed hook input", async () => {
  const { io, out, err } = harness({ stdin: "not json" });
  await runStopHook(io);
  assert.deepEqual(out, []);
  assert.match(err.join(""), /allowing the stop/);
});
