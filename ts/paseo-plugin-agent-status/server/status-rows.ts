import { randomUUID } from "node:crypto";
import type { AgentToolContext } from "@getpaseo/plugin/server";
import { STATUS_ROW_KIND, STATUS_ROW_VERSION, type StatusRow } from "../shared/status.ts";

type PaseoApi = AgentToolContext["paseo"];

export interface Status {
  summary: string;
  waitingOn?: string;
  setAt: number;
}

interface AgentState {
  status?: Status;
  rowId?: string;
}

/**
 * Keeps one visible status row per agent, as the last row of its chat. A row appended
 * mid-turn would end up wherever `set_status` was called, buried under later output, so
 * `record` only stores the status and `showAtBottom` places it once the turn has ended.
 * A row can't be deleted, only overwritten under the same id in its original place, so
 * each placement gets a fresh row and the previous one is overwritten as superseded.
 */
export function createStatusRows() {
  const agents = new Map<string, AgentState>();
  // Turn ends for one agent are serialised so two placements can't each supersede the
  // same old row and leave both new rows visible.
  const queues = new Map<string, Promise<void>>();

  async function append(paseo: PaseoApi, agentId: string, id: string, data: StatusRow) {
    await paseo.agents.ref(agentId).timeline.append({
      type: "plugin",
      id,
      kind: STATUS_ROW_KIND,
      version: STATUS_ROW_VERSION,
      data,
    });
  }

  async function placeNow(paseo: PaseoApi, agentId: string) {
    const state = agents.get(agentId);
    if (!state?.status) return;
    const rowId = `status-${randomUUID()}`;
    try {
      await append(paseo, agentId, rowId, { ...state.status });
    } catch (error) {
      console.error(`agent-status: could not append the status row for agent ${agentId}`, error);
      return;
    }
    const previous = state.rowId;
    state.rowId = rowId;
    if (previous === undefined) return;
    try {
      await append(paseo, agentId, previous, { superseded: true });
    } catch (error) {
      console.error(`agent-status: could not hide the previous status row for agent ${agentId}`, error);
    }
  }

  return {
    record(agentId: string, status: Status): void {
      const state = agents.get(agentId) ?? {};
      state.status = status;
      agents.set(agentId, state);
    },

    /** Moves the agent's latest status to the bottom of its chat; a no-op until it has one. */
    showAtBottom(paseo: PaseoApi, agentId: string): Promise<void> {
      const next = (queues.get(agentId) ?? Promise.resolve()).then(() => placeNow(paseo, agentId));
      queues.set(agentId, next);
      return next;
    },
  };
}
