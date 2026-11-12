import { randomUUID } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import { STATUS_ROW_KIND, STATUS_ROW_VERSION, type StatusRow } from "../shared/status.ts";
import type { StatusStore } from "./status-store.ts";

/** The slice of the Paseo API this module uses; the real one satisfies it. */
export interface TimelineAppender {
  agents: {
    ref(agentId: string): {
      timeline: {
        append(item: { type: "plugin"; id: string; kind: string; version: number; data: StatusRow }): Promise<unknown>;
      };
    };
  };
}

export interface Status {
  summary: string;
  waitingOn?: string;
  setAt: number;
}

// The session-open hook runs before the daemon registers the agent, so a restore has
// to wait for it. Opening resumes the provider session, which can take a few seconds.
const RESTORE_RETRY_MS = 250;
const RESTORE_ATTEMPTS = 120;

function isUnknownAgent(error: unknown): boolean {
  return error instanceof Error && error.message.includes("Unknown agent");
}

/**
 * Keeps one visible status row per agent, as the last row of its chat. A row appended
 * mid-turn would end up wherever `set_status` was called, buried under later output, so
 * `record` only stores the status and `showAtBottom` places it once the turn has ended.
 * A row can't be deleted, only overwritten under the same id in its original place, so
 * each placement gets a fresh row and the previous one is overwritten as superseded.
 *
 * Rows live in the daemon's memory and are gone after a restart, so the latest status
 * and its row id are saved, and `restore` re-appends that row when the agent next opens.
 */
export function createStatusRows(store: StatusStore) {
  // Placements and restores for one agent are serialised: two placements could otherwise
  // each supersede the same old row, and a restore could re-show a replaced row.
  const queues = new Map<string, Promise<void>>();

  function enqueue(agentId: string, work: () => Promise<void>): Promise<void> {
    const next = (queues.get(agentId) ?? Promise.resolve()).then(work);
    queues.set(agentId, next);
    return next;
  }

  async function append(paseo: TimelineAppender, agentId: string, id: string, data: StatusRow) {
    await paseo.agents.ref(agentId).timeline.append({
      type: "plugin",
      id,
      kind: STATUS_ROW_KIND,
      version: STATUS_ROW_VERSION,
      data,
    });
  }

  async function placeNow(paseo: TimelineAppender, agentId: string) {
    const saved = store.get(agentId);
    if (!saved) return;
    const rowId = `status-${randomUUID()}`;
    try {
      await append(paseo, agentId, rowId, { ...saved.status });
    } catch (error) {
      console.error(`agent-status: could not append the status row for agent ${agentId}`, error);
      return;
    }
    store.set(agentId, { ...saved, rowId });
    if (saved.rowId === undefined) return;
    try {
      await append(paseo, agentId, saved.rowId, { superseded: true });
    } catch (error) {
      console.error(`agent-status: could not hide the previous status row for agent ${agentId}`, error);
    }
  }

  async function restoreNow(paseo: TimelineAppender, agentId: string) {
    for (let attempt = 0; attempt < RESTORE_ATTEMPTS; attempt++) {
      const saved = store.get(agentId);
      if (!saved?.rowId) return;
      try {
        // Under the saved id, so a session that reopens without a restart replaces its
        // row in place rather than gaining a second one.
        await append(paseo, agentId, saved.rowId, { ...saved.status });
        return;
      } catch (error) {
        if (!isUnknownAgent(error)) {
          console.error(`agent-status: could not restore the status row for agent ${agentId}`, error);
          return;
        }
      }
      await delay(RESTORE_RETRY_MS);
    }
    console.warn(`agent-status: agent ${agentId} never finished opening; its status row was not restored`);
  }

  return {
    record(agentId: string, status: Status): void {
      store.set(agentId, { ...store.get(agentId), status });
    },

    /** Moves the agent's latest status to the bottom of its chat; a no-op until it has one. */
    showAtBottom(paseo: TimelineAppender, agentId: string): Promise<void> {
      return enqueue(agentId, () => placeNow(paseo, agentId));
    },

    /** Re-shows the saved row once the opening agent is registered; a no-op until one has been placed. */
    restore(paseo: TimelineAppender, agentId: string): Promise<void> {
      return enqueue(agentId, () => restoreNow(paseo, agentId));
    },
  };
}
