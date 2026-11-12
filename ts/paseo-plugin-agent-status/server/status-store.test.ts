import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { test } from "node:test";
import { openStatusStore } from "./status-store.ts";

const status = { summary: "Fixing the auth test", waitingOn: "CI", setAt: 1_000 };

async function stateFile(contents?: string): Promise<string> {
  const file = path.join(await mkdtemp(path.join(tmpdir(), "agent-status-")), "plugin-state", "agent-status.json");
  if (contents !== undefined) {
    await mkdir(path.dirname(file), { recursive: true });
    await writeFile(file, contents);
  }
  return file;
}

function captureWarnings(): { warnings: string[]; restore(): void } {
  const warnings: string[] = [];
  const original = console.warn;
  console.warn = (...data: unknown[]) => void warnings.push(data.map(String).join(" "));
  return { warnings, restore: () => void (console.warn = original) };
}

test("a saved status survives reopening the store", async () => {
  const file = await stateFile();
  const first = await openStatusStore(file);
  first.set("agent-1", { status, rowId: "status-a" });
  await first.flush();

  const second = await openStatusStore(file);
  assert.deepEqual(second.get("agent-1"), { status, rowId: "status-a" });
});

test("a missing file starts empty without a warning", async () => {
  const capture = captureWarnings();
  try {
    const store = await openStatusStore(await stateFile());
    assert.equal(store.get("agent-1"), undefined);
    assert.deepEqual(capture.warnings, []);
  } finally {
    capture.restore();
  }
});

for (const [label, contents] of [
  ["not JSON", "{ nope"],
  ["the wrong shape", JSON.stringify({ version: 1, agents: { "agent-1": { status: "busy" } } })],
  ["an unknown version", JSON.stringify({ version: 2, agents: {} })],
] as const) {
  test(`a file that is ${label} starts empty, warns, and is overwritten by the next save`, async () => {
    const file = await stateFile(contents);
    const capture = captureWarnings();
    try {
      const store = await openStatusStore(file);
      assert.equal(store.get("agent-1"), undefined);
      assert.match(capture.warnings.join("\n"), /ignoring malformed/);
      store.set("agent-1", { status });
      await store.flush();
      assert.deepEqual(JSON.parse(await readFile(file, "utf8")), { version: 1, agents: { "agent-1": { status } } });
    } finally {
      capture.restore();
    }
  });
}

test("retain drops agents that no longer exist", async () => {
  const file = await stateFile();
  const store = await openStatusStore(file);
  store.set("kept", { status });
  store.set("archived", { status });
  store.retain(new Set(["kept"]));
  await store.flush();
  assert.deepEqual(Object.keys(JSON.parse(await readFile(file, "utf8")).agents), ["kept"]);
});
