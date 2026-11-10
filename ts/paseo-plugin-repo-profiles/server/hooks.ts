import type { PluginHookContext, PluginServerContext } from "@getpaseo/plugin/server";
import { WARNING_KIND, WARNING_VERSION, type WarningData } from "../shared/timeline.ts";
import { decide, withExtraArgs, type Deps } from "./resolve.ts";
import { TOKEN_ENV, withoutToken, type WarningLedger } from "./warnings.ts";

type Server = Pick<PluginServerContext, "addHook">;
type Paseo = Pick<PluginHookContext["paseo"], "agents">;

export interface HookDeps {
  resolve(signal: AbortSignal): Deps;
  ledger: WarningLedger;
}

// One row per agent, so a fixed id is enough; reusing it would replace the row.
const ROW_ID = "repo-profiles-warning";

// Every failure leaves the request unchanged, because a throw from a before hook
// would fail agent creation.
export function registerHooks(server: Server, deps: HookDeps): () => void {
  const removers = [
    server.addHook("agent.create.before", async ({ request }, { signal }) => {
      const { cwd } = request.config;
      let warning: WarningData | undefined;
      let config = request.config;
      try {
        const decision = await decide(request.config, deps.resolve(signal));
        if (Object.keys(decision.set).length > 0) {
          console.info(`repo-profiles: loading ${decision.key} ${decision.loaded.join(" and ")} in ${cwd}`);
          config = withExtraArgs(request.config, decision.set);
        }
        if (decision.problems.length > 0) {
          warning = { problems: decision.problems, loaded: decision.loaded };
          if (decision.key !== undefined) warning.key = decision.key;
        }
      } catch (error) {
        warning = { problems: [{ reason: error instanceof Error ? error.message : String(error) }], loaded: [] };
      }
      if (warning === undefined) return config === request.config ? undefined : { ...request, config };
      for (const { field, reason, detail } of warning.problems) {
        const scope = field === undefined ? "" : `${field}: `;
        console.warn(`repo-profiles: ${cwd}: ${scope}${reason}${detail === undefined ? "" : `: ${detail}`}`);
      }
      const token = deps.ledger.record(warning);
      return { ...request, config, env: { ...request.env, [TOKEN_ENV]: token } };
    }),

    // Runs on every open, not only creation: Paseo saves the creation env with the
    // agent, so the token comes back on resume and has to be stripped each time.
    server.addHook("agent.open.before", async ({ request }) => {
      // A creation that failed after claiming leaves an entry under its id, and Paseo
      // reuses ids when it re-creates a stored agent.
      if (request.reason === "create") deps.ledger.forget(request.agentId);
      const token = request.env[TOKEN_ENV];
      if (token === undefined) return;
      if (request.reason === "create") deps.ledger.claim(token, request.agentId);
      return { ...request, env: withoutToken(request.env) };
    }),

    server.addHook("agent.create.after", async ({ agent }, { paseo }) => {
      const warning = deps.ledger.take(agent.id);
      if (warning === undefined) return;
      await postWarning(paseo, agent.id, warning);
    }),
  ];
  return () => removers.forEach((remove) => remove());
}

async function postWarning(paseo: Paseo, agentId: string, data: WarningData) {
  try {
    await paseo.agents.ref(agentId).timeline.append({
      type: "plugin",
      id: ROW_ID,
      kind: WARNING_KIND,
      version: WARNING_VERSION,
      data,
    });
  } catch (error) {
    console.warn(
      `repo-profiles: could not post a warning to agent ${agentId}: ${error instanceof Error ? error.message : error}`,
    );
  }
}
