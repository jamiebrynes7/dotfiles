import { randomUUID } from "node:crypto";
import type { AgentToolContext } from "@getpaseo/plugin/server";
import { STATUS_ROW_KIND, STATUS_ROW_VERSION, type StatusRow } from "../shared/status.ts";

type PaseoApi = AgentToolContext["paseo"];

export interface Status {
  summary: string;
  waitingOn?: string;
  setAt: number;
}

/**
 * Keeps one visible status row per agent. A row can't be deleted, only overwritten under
 * the same id, and an overwrite keeps the row's original place in the chat, so each new
 * status gets a fresh row at the bottom and the previous one is overwritten as superseded.
 */
export function createStatusRows() {
  const currentRowIds = new Map<string, string>();
  // Claude can issue tool calls in parallel; without a per-agent queue two concurrent
  // publishes could each supersede the same old row and leave both new rows visible.
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

  async function publishNow(paseo: PaseoApi, agentId: string, status: Status) {
    const rowId = `status-${randomUUID()}`;
    try {
      await append(paseo, agentId, rowId, { ...status });
    } catch (error) {
      // The agent shouldn't retry because of a display failure, so this is only logged.
      console.error(`agent-status: could not append the status row for agent ${agentId}`, error);
      return;
    }
    const previous = currentRowIds.get(agentId);
    currentRowIds.set(agentId, rowId);
    if (previous === undefined) return;
    try {
      await append(paseo, agentId, previous, { superseded: true });
    } catch (error) {
      console.error(`agent-status: could not hide the previous status row for agent ${agentId}`, error);
    }
  }

  return {
    publish(paseo: PaseoApi, agentId: string, status: Status): Promise<void> {
      const next = (queues.get(agentId) ?? Promise.resolve()).then(() => publishNow(paseo, agentId, status));
      queues.set(agentId, next);
      return next;
    },
  };
}
