import { defineAgentTool, type PluginHookContext, type PluginServerContext } from "@getpaseo/plugin/server";
import { createStatusRows } from "./server/status-rows.ts";
import { openStatusStore } from "./server/status-store.ts";
import { statusInputSchema } from "./shared/status.ts";
import { SET_STATUS_TOOL, STATUS_ENV } from "./shared/tool-contract.ts";

const DESCRIPTION = `Set the status shown at the bottom of your chat, so the user can tell at a glance what you are doing and what you are waiting on when they come back to you among many parallel agents. It appears when your turn ends.

Call it when you start a task, whenever your phase changes, and always before you end a turn, even if the status is unchanged.

- summary: the task and where it stands, e.g. "Fixing the flaky auth test" or "Auth test fixed, all tests pass". Don't repeat what you are blocked on here; that goes in waiting_on. At most 80 characters.
- waiting_on: set whenever you are blocked, e.g. "CI on #1234". Use "you" (optionally with what you need, e.g. "you: pick raise or clamp") when you need the user's input or have finished. Omit it while you are working. At most 60 characters.`;

const PAGE_LIMIT = 200;

// Every non-archived agent the daemon knows of. A directory read, unlike a timeline
// fetch, never loads an agent.
async function listAgentIds(paseo: PluginHookContext["paseo"]): Promise<Set<string>> {
  const ids = new Set<string>();
  let cursor: string | undefined;
  do {
    const { entries, pageInfo } = await paseo.agents.list({
      page: { limit: PAGE_LIMIT, ...(cursor ? { cursor } : {}) },
    });
    for (const { agent } of entries) ids.add(agent.id);
    cursor = pageInfo.hasMore ? (pageInfo.nextCursor ?? undefined) : undefined;
  } while (cursor);
  return ids;
}

export default function contribute(server: PluginServerContext) {
  const store = openStatusStore();
  const rows = store.then(createStatusRows);

  // The server context has no Paseo handle, so pruning waits for the first hook to
  // bring one. Pruning here rather than on an archive hook also catches agents removed
  // while the plugin was off.
  let pruned: Promise<void> | undefined;
  function pruneOnce(paseo: PluginHookContext["paseo"]): void {
    pruned ??= Promise.all([store, listAgentIds(paseo)])
      .then(([saved, ids]) => saved.retain(ids))
      .catch((error: unknown) => console.warn("agent-status: could not list agents to prune saved statuses", error));
  }

  const setStatus = defineAgentTool({
    name: SET_STATUS_TOOL,
    title: "Set status",
    description: DESCRIPTION,
    input: statusInputSchema,
    async execute(input, { agent }) {
      (await rows).record(agent.id, {
        summary: input.summary,
        ...(input.waiting_on ? { waitingOn: input.waiting_on } : {}),
        setAt: Date.now(),
      });
      return { text: "Status updated." };
    },
  });

  const removeOpenHook = server.addHook("agent.open.before", async ({ request }, { paseo }) => {
    pruneOnce(paseo);
    if (request.purpose !== "interactive") return request;
    // Not awaited: the agent is registered only after this hook returns, and the
    // restore waits for that.
    void rows.then((statusRows) => statusRows.restore(paseo, request.agentId));
    return {
      ...request,
      tools: [...request.tools, setStatus],
      env: { ...request.env, [STATUS_ENV]: "1" },
    };
  });
  // Every outcome counts: a cancelled or failed turn still leaves the agent idle with
  // its last status worth showing.
  const removeTurnHook = server.addHook("agent.turn.after", async ({ agent }, { paseo }) => {
    pruneOnce(paseo);
    await (await rows).showAtBottom(paseo, agent.id);
  });
  return async () => {
    removeOpenHook();
    removeTurnHook();
    await (await store).flush();
  };
}
