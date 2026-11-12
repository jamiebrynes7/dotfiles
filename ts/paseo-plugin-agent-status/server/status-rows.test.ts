import assert from "node:assert/strict";
import { test } from "node:test";
import type { StatusRow } from "../shared/status.ts";
import { createStatusRows, type TimelineAppender } from "./status-rows.ts";
import type { StatusStore, StoredAgentStatus } from "./status-store.ts";

function memoryStore(): StatusStore {
  const agents = new Map<string, StoredAgentStatus>();
  return {
    get: (id) => agents.get(id),
    set: (id, value) => void agents.set(id, value),
    retain: (ids) => {
      for (const id of agents.keys()) if (!ids.has(id)) agents.delete(id);
    },
    flush: async () => {},
  };
}

/** A timeline that keeps rows in place on re-append, and rejects appends until the agent is registered. */
function fakeTimeline(options: { unknownFor?: number } = {}) {
  let unknown = options.unknownFor ?? 0;
  const rows: { id: string; data: StatusRow }[] = [];
  const paseo: TimelineAppender = {
    agents: {
      ref: () => ({
        timeline: {
          async append({ id, data }) {
            if (unknown > 0) {
              unknown--;
              throw new Error("Unknown agent 'agent-1'");
            }
            const existing = rows.find((row) => row.id === id);
            if (existing) existing.data = data;
            else rows.push({ id, data });
            return {};
          },
        },
      }),
    },
  };
  const visible = () => rows.filter((row) => !("superseded" in row.data)).map((row) => row.data);
  return { paseo, rows, visible };
}

const first = { summary: "Fixing the auth test", setAt: 1 };
const second = { summary: "Auth test fixed", waitingOn: "you", setAt: 2 };

test("each turn end leaves only the newest status visible, as the last row", async () => {
  const rows = createStatusRows(memoryStore());
  const timeline = fakeTimeline();
  rows.record("agent-1", first);
  await rows.showAtBottom(timeline.paseo, "agent-1");
  rows.record("agent-1", second);
  await rows.showAtBottom(timeline.paseo, "agent-1");
  assert.deepEqual(timeline.visible(), [second]);
  assert.deepEqual(timeline.rows.at(-1)?.data, second);
});

test("a turn end before any status adds nothing", async () => {
  const timeline = fakeTimeline();
  await createStatusRows(memoryStore()).showAtBottom(timeline.paseo, "agent-1");
  assert.deepEqual(timeline.rows, []);
});

test("restore re-shows the saved row in a fresh timeline after a restart", async () => {
  const store = memoryStore();
  await (async () => {
    const before = createStatusRows(store);
    before.record("agent-1", second);
    await before.showAtBottom(fakeTimeline().paseo, "agent-1");
  })();

  const afterRestart = createStatusRows(store);
  const timeline = fakeTimeline();
  await afterRestart.restore(timeline.paseo, "agent-1");
  assert.deepEqual(timeline.visible(), [second]);
  assert.equal(timeline.rows[0]?.id, store.get("agent-1")?.rowId);
});

test("restore waits for the opening agent to be registered", async () => {
  const store = memoryStore();
  const rows = createStatusRows(store);
  rows.record("agent-1", first);
  await rows.showAtBottom(fakeTimeline().paseo, "agent-1");

  const timeline = fakeTimeline({ unknownFor: 2 });
  await rows.restore(timeline.paseo, "agent-1");
  assert.deepEqual(timeline.visible(), [first]);
});

test("restoring into a timeline that still has the row replaces it in place", async () => {
  const rows = createStatusRows(memoryStore());
  const timeline = fakeTimeline();
  rows.record("agent-1", first);
  await rows.showAtBottom(timeline.paseo, "agent-1");
  await rows.restore(timeline.paseo, "agent-1");
  assert.equal(timeline.rows.length, 1);
  assert.deepEqual(timeline.visible(), [first]);
});

test("a restore queued behind a turn end shows the newer row, not the replaced one", async () => {
  const rows = createStatusRows(memoryStore());
  const timeline = fakeTimeline();
  rows.record("agent-1", first);
  await rows.showAtBottom(timeline.paseo, "agent-1");
  rows.record("agent-1", second);
  await Promise.all([rows.showAtBottom(timeline.paseo, "agent-1"), rows.restore(timeline.paseo, "agent-1")]);
  assert.deepEqual(timeline.visible(), [second]);
});

test("restore does nothing for an agent that never had a row placed", async () => {
  const rows = createStatusRows(memoryStore());
  rows.record("agent-1", first);
  const timeline = fakeTimeline();
  await rows.restore(timeline.paseo, "agent-1");
  assert.deepEqual(timeline.rows, []);
});
