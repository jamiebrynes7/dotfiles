import type { PluginHandlerContext, PluginServerContext } from "@getpaseo/plugin/server";
import { openStore } from "./server/store";
import { listResponseTimes } from "./shared/rpc";

const PAGE_LIMIT = 200;

// Every non-archived agent the daemon knows of. A directory read, unlike a timeline
// fetch, never loads an agent.
async function listAgentIds(paseo: PluginHandlerContext["paseo"]): Promise<Set<string>> {
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

// The daemon half exists so the client never has to read a timeline: a timeline
// fetch runs `ensureAgentLoaded`, which resumes a stored agent's provider session.
// `agent.turn_ended` fires only for live turns, so recording here wakes nothing.
export default function contribute(server: PluginServerContext) {
  const store = openStore();

  // Costly but unavoidable in 0.11.4: subscribing ships the agent's whole timeline
  // to this subprocess on every turn end, and there is no slimmer hook. Every outcome
  // counts, so a cancelled or failed turn also reads "Just now", as the client stamp does.
  server.on("agent.turn_ended", async (event) => {
    (await store).record(event.agent.id, Date.now());
  });

  // Pruning here rather than on an archive hook also catches agents deleted, or
  // archived while the plugin was off. Clients call this once per directory snapshot.
  server.handle(listResponseTimes, async (_input, { paseo }) => {
    const times = await store;
    try {
      times.retain(await listAgentIds(paseo));
    } catch (error) {
      console.warn("last-response: could not list agents to prune", error);
    }
    return { respondedAt: times.all() };
  });

  return async () => {
    await (await store).flush();
  };
}
