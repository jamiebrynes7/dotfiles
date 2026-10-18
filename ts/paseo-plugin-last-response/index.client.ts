import type { PluginButtonRegistration, PluginClientContext } from "@getpaseo/plugin/client";
import { formatAge } from "./client/relative-time";
import { listResponseTimes } from "./shared/rpc";

const TICK_MS = 30_000;
const RETRY_MS = 10_000;

interface AgentEntry {
  id: string;
  workspaceId?: string | null;
  status: string;
  archivedAt?: string | null;
  pendingPermissions?: readonly unknown[];
}

interface Tracked {
  workspaceId: string;
  pill: PluginButtonRegistration;
  running: boolean;
  waiting: boolean;
  respondedAt: number | null;
  shown: string;
}

// Times come from the daemon half over RPC, never from `timeline.refetch`: a timeline
// fetch runs `ensureAgentLoaded`, which resumes a stored agent's provider session, and
// the client cannot tell which listed agents are loaded.
export default function contribute(client: PluginClientContext) {
  const tracked = new Map<string, Tracked>();
  const lifetime = new AbortController();
  let stopped = false;
  let retryTimer: number | undefined;

  function render(agent: Tracked) {
    let next: { visible: boolean; label?: string; title?: string };
    if (agent.waiting) {
      next = { visible: true, label: "Waiting on you", title: "Agent is waiting for your input" };
    } else if (agent.running) {
      next = { visible: true, label: "Responding…", title: "Agent is responding" };
    } else if (agent.respondedAt !== null) {
      next = {
        visible: true,
        label: formatAge(Date.now() - agent.respondedAt),
        title: `Last response at ${new Date(agent.respondedAt).toLocaleString()}`,
      };
    } else {
      next = { visible: false };
    }
    const shown = JSON.stringify(next);
    if (shown === agent.shown) return;
    agent.shown = shown;
    agent.pill.update(next);
  }

  // A sync replaces a local stamp outright rather than taking the later of the two:
  // client and daemon clocks can differ, and a skewed local stamp would otherwise
  // outrank every later daemon time. The stamp only bridges the gap until a sync.
  function syncFromDaemon({ retry }: { retry: boolean }) {
    client
      .rpc(listResponseTimes, {})
      .then(({ respondedAt }) => {
        if (stopped) return;
        for (const [id, agent] of tracked) {
          const at = respondedAt[id];
          if (at !== undefined) agent.respondedAt = at;
          render(agent);
        }
      })
      .catch((error: unknown) => {
        if (stopped) return;
        console.warn("last-response: could not read response times", error);
        // The daemon half may be restarting; otherwise the next try is the next reconnect.
        if (retry) retryTimer = setTimeout(() => syncFromDaemon({ retry: false }), RETRY_MS);
      });
  }

  function untrack(id: string) {
    tracked.get(id)?.pill.remove();
    tracked.delete(id);
  }

  function track(entry: AgentEntry, { live }: { live: boolean }) {
    if (stopped) return;
    const workspaceId = entry.workspaceId;
    let agent = tracked.get(entry.id);
    if (!workspaceId || entry.archivedAt) {
      untrack(entry.id);
      return;
    }
    // A pill is bound to one workspace's composer, so a move re-registers it.
    if (agent && agent.workspaceId !== workspaceId) {
      untrack(entry.id);
      agent = undefined;
    }
    const running = entry.status === "running";
    const waiting = (entry.pendingPermissions?.length ?? 0) > 0;
    if (!agent) {
      agent = {
        workspaceId,
        pill: client.addComposerPill({
          id: "last-response",
          workspaceId,
          agentId: entry.id,
          button: {
            title: "Last response",
            icon: "Clock",
            visible: false,
            behavior: { kind: "action", onPress() {} },
          },
        }),
        running,
        waiting,
        respondedAt: null,
        shown: "",
      };
      tracked.set(entry.id, agent);
      render(agent);
      return;
    }
    // Only a live update is a turn ending now. A snapshot after a reconnect only
    // shows that it ended at some point; the daemon sync supplies when.
    if (live && agent.running && !running) agent.respondedAt = Date.now();
    agent.running = running;
    agent.waiting = waiting;
    render(agent);
  }

  void client.paseo.agents
    .list({ subscribe: {}, signal: lifetime.signal })
    .then(({ subscription }) => {
      subscription.subscribe({
        // Initial load and every reconnect: turns may have ended while disconnected.
        snapshot: ({ entries }) => {
          const present = new Set(entries.map(({ agent }) => agent.id));
          for (const id of [...tracked.keys()]) if (!present.has(id)) untrack(id);
          for (const { agent } of entries) track(agent, { live: false });
          clearTimeout(retryTimer);
          syncFromDaemon({ retry: true });
        },
        update: (message) => {
          if (message.type !== "agent_update") return;
          const update = message.payload;
          if (update.kind === "remove") untrack(update.agentId);
          else track(update.agent, { live: true });
        },
      });
      return undefined;
    })
    .catch((error: unknown) => {
      if (!stopped) console.error("last-response: agent observation failed", error);
    });

  const ticker = setInterval(() => {
    for (const agent of tracked.values()) render(agent);
  }, TICK_MS);

  return () => {
    stopped = true;
    clearInterval(ticker);
    clearTimeout(retryTimer);
    lifetime.abort();
    for (const id of [...tracked.keys()]) untrack(id);
  };
}
