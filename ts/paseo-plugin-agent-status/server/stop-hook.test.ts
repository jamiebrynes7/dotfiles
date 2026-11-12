import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

// Runs the real hook script the way writeShellApplication does, with jq from PATH.
const HOOK = path.join(path.dirname(fileURLToPath(import.meta.url)), "stop-hook.sh");

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

async function transcriptFile(contents: string): Promise<string> {
  const file = path.join(await mkdtemp(path.join(tmpdir(), "agent-status-hook-")), "transcript.jsonl");
  await writeFile(file, contents);
  return file;
}

function runHook(options: { stdin: string; env?: Record<string, string> }) {
  const result = spawnSync("bash", ["-euo", "pipefail", HOOK], {
    input: options.stdin,
    encoding: "utf8",
    env: { PATH: process.env.PATH ?? "", ...(options.env ?? { PASEO_STATUS: "1" }) },
  });
  return { status: result.status, stdout: result.stdout, stderr: result.stderr };
}

async function decide(transcript: string, extra: Record<string, unknown> = {}) {
  const stdin = JSON.stringify({ transcript_path: await transcriptFile(transcript), stop_hook_active: false, ...extra });
  return runHook({ stdin });
}

function assertBlocked(result: ReturnType<typeof runHook>) {
  assert.equal(result.status, 0);
  const output = JSON.parse(result.stdout);
  assert.equal(output.decision, "block");
  assert.match(output.reason, /^Call set_status /);
  assert.match(output.reason, /"Status updated\."/);
}

function assertAllowed(result: ReturnType<typeof runHook>) {
  assert.equal(result.status, 0);
  assert.equal(result.stdout, "");
}

test("a status set after the latest prompt allows the stop", async () => {
  assertAllowed(await decide(jsonl(prompt("fix it"), toolUse("Bash"), toolResult(), toolUse(SET_STATUS), toolResult(), reply("done"))));
});

test("a status set only before the latest prompt blocks", async () => {
  assertBlocked(await decide(jsonl(prompt("fix it"), toolUse(SET_STATUS), toolResult(), stringPrompt("thanks"), reply("np"))));
});

test("no status set at all blocks", async () => {
  assertBlocked(await decide(jsonl(prompt("fix it"), toolUse("Bash"), toolResult(), reply("done"))));
});

test("tool results, meta entries and subagent entries don't start a new turn", async () => {
  const meta = { ...prompt("<command-name>/clear</command-name>"), isMeta: true };
  const subagentPrompt = { ...prompt("subagent task"), isSidechain: true };
  assertAllowed(await decide(jsonl(prompt("go"), toolUse(SET_STATUS), toolResult(), meta, subagentPrompt, toolResult(), reply("done"))));
});

test("a subagent's set_status call does not count for the main agent", async () => {
  assertBlocked(await decide(jsonl(prompt("go"), toolUse(SET_STATUS, { isSidechain: true }), reply("done"))));
});

test("a set_status tool from another MCP server does not count", async () => {
  assertBlocked(await decide(jsonl(prompt("go"), toolUse("mcp__other__set_status"), reply("done"))));
});

test("a torn last line is skipped", async () => {
  assertAllowed(await decide(jsonl(prompt("go"), toolUse(SET_STATUS)) + '{"type":"assis'));
});

test("does nothing outside a Paseo agent with the plugin", async () => {
  const result = runHook({ stdin: "not even json", env: {} });
  assert.deepEqual(result, { status: 0, stdout: "", stderr: "" });
});

test("allows the stop when Claude is already continuing because of a stop hook", async () => {
  assertAllowed(await decide(jsonl(prompt("go"), reply("done")), { stop_hook_active: true }));
});

test("fails open on an unreadable transcript and says so on stderr", async () => {
  const result = runHook({ stdin: JSON.stringify({ transcript_path: "/nonexistent/t.jsonl", stop_hook_active: false }) });
  assertAllowed(result);
  assert.match(result.stderr, /cannot read transcript \/nonexistent\/t\.jsonl; allowing the stop/);
});

test("fails open on malformed hook input", async () => {
  for (const stdin of ["not json", '"a string"', "{}"]) {
    const result = runHook({ stdin });
    assertAllowed(result);
    assert.match(result.stderr, /allowing the stop/, `stdin: ${stdin}`);
  }
});
