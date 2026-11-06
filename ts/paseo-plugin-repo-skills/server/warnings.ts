import { randomUUID } from "node:crypto";
import type { WarningData } from "../shared/timeline.ts";

// agent.create.before has no agent id, so a warning travels with the request as a
// one-off token in its env. agent.open.before, which does have the id, claims it and
// strips the variable; agent.create.after posts it. A creation that fails never
// claims or posts, so its warning cannot reach another agent.
//
// Costs of this design, accepted over pairing by cwd (which can hand a failed
// creation's warning to a retry in the same directory):
// - Having an agent.open.before hook makes Paseo reload every live agent's session on
//   its next prompt whenever this plugin starts, stops or restarts.
// - The token is not private: other plugins' hooks that run after this one see it,
//   and Paseo saves it in the agent's launchEnv.
export const TOKEN_ENV = "PASEO_REPO_SKILLS_WARNING";

// Far longer than any creation takes. Only bounds what failed creations leave behind.
export const WARNING_TTL_MS = 5 * 60_000;

interface Entry {
  data: WarningData;
  at: number;
}

export interface WarningLedger {
  record(data: WarningData): string;
  claim(token: string, agentId: string): void;
  forget(agentId: string): void;
  take(agentId: string): WarningData | undefined;
}

export function createWarningLedger(now: () => number = Date.now): WarningLedger {
  const byToken = new Map<string, Entry>();
  const byAgent = new Map<string, Entry>();

  function prune() {
    const cutoff = now() - WARNING_TTL_MS;
    for (const map of [byToken, byAgent]) {
      for (const [key, entry] of map) if (entry.at < cutoff) map.delete(key);
    }
  }

  return {
    record(data) {
      prune();
      const token = randomUUID();
      byToken.set(token, { data, at: now() });
      return token;
    },
    claim(token, agentId) {
      prune();
      const entry = byToken.get(token);
      if (entry === undefined) return;
      byToken.delete(token);
      byAgent.set(agentId, entry);
    },
    forget(agentId) {
      byAgent.delete(agentId);
    },
    take(agentId) {
      prune();
      const entry = byAgent.get(agentId);
      byAgent.delete(agentId);
      return entry?.data;
    },
  };
}

export function withoutToken(env: Record<string, string>): Record<string, string> {
  const { [TOKEN_ENV]: _token, ...rest } = env;
  return rest;
}
