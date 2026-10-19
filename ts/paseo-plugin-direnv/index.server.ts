import type { PluginServerContext } from "@getpaseo/plugin/server";
import path from "node:path";
import { evaluate, TIMEOUT_MS } from "./server/evaluate";
import { merge } from "./server/merge";
import {
  allowNewWorktree,
  COMMAND_TIMEOUT_MS,
  isInside,
  MAX_COMMANDS,
} from "./server/worktree-allow";

// The longest an open waits on a pending worktree allow, out of the evaluation's
// own budget. Covers the allow's whole command chain, so only a stuck allow is cut short.
const ALLOW_WAIT_MS = COMMAND_TIMEOUT_MS * MAX_COMMANDS + 1_000;

// Single-quoted so a suggested command survives copy-paste for a path with spaces.
function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

function settledWithin(work: Promise<unknown>[], ms: number, signal: AbortSignal): Promise<void> {
  if (signal.aborted) return Promise.resolve();
  return new Promise((resolve) => {
    const done = () => {
      clearTimeout(timer);
      signal.removeEventListener("abort", done);
      resolve();
    };
    const timer = setTimeout(done, ms);
    signal.addEventListener("abort", done, { once: true });
    void Promise.allSettled(work).then(done);
  });
}

// Every open re-evaluates and nothing is cached: env overrides are not persisted, so
// each create, resume, refresh and import comes through here, and an `.envrc` edited
// since it was allowed is refused at the next open instead of running stale.
// Logs carry outcomes, directories and variable names, never values.
export default function contribute(server: PluginServerContext) {
  let reportedUnavailable = false;
  // Worktree allows in flight, by workspace directory. Events and hooks share the
  // plugin's IPC channel and start in arrival order, so an entry set before the
  // event handler's first await is visible to every later open.
  const pendingAllows = new Map<string, Promise<unknown>>();

  server.on("workspace.created", async ({ workspace }) => {
    const { cwd } = workspace;
    const allow = allowNewWorktree(cwd).then(
      (decision) => {
        if (decision.kind === "allowed") {
          console.info(
            `direnv: allowed new worktree ${decision.worktree} (source ${decision.source} is allowed)`,
          );
        } else {
          console.info(`direnv: no allow for workspace ${cwd}: ${decision.reason}`);
        }
      },
      (error: unknown) => {
        console.warn(
          `direnv: allow for workspace ${cwd} failed: ${error instanceof Error ? error.message : error}`,
        );
      },
    );
    pendingAllows.set(cwd, allow);
    await allow;
    if (pendingAllows.get(cwd) === allow) pendingAllows.delete(cwd);
  });

  server.before("agent.session_open", async ({ request }, { signal }) => {
    // An archived agent opened to read its timeline; its directory may be gone.
    if (request.purpose === "history") return;

    const { cwd } = request;
    const started = Date.now();
    const pending = [...pendingAllows]
      .filter(([dir]) => dir === cwd || isInside(cwd, dir))
      .map(([, allow]) => allow);
    if (pending.length > 0) await settledWithin(pending, ALLOW_WAIT_MS, signal);
    const budget = TIMEOUT_MS - (Date.now() - started);

    const warm = `\`direnv exec ${shellQuote(cwd)} true\``;
    const result = await evaluate(cwd, signal, budget);
    switch (result.kind) {
      case "unavailable":
        if (!reportedUnavailable) {
          reportedUnavailable = true;
          console.info("direnv: no direnv on the daemon PATH; launching agents unchanged");
        }
        return;
      case "none":
        return;
      case "blocked": {
        const dir = shellQuote(path.dirname(result.envrc));
        console.warn(`direnv: refused ${request.reason} in ${cwd}: ${result.envrc} is blocked`);
        throw new Error(
          `.envrc at ${result.envrc} is blocked by direnv. Run \`direnv allow ${dir}\`, then retry.`,
        );
      }
      case "failed":
        console.warn(`direnv: refused ${request.reason} in ${cwd}: ${result.exit}`);
        throw new Error(
          [
            `direnv failed in ${cwd} (${result.exit}):`,
            result.stderrTail,
            `Run ${warm} in a terminal to see the full output.`,
          ]
            .filter((line) => line !== "")
            .join("\n"),
        );
      case "timeout":
        console.warn(`direnv: refused ${request.reason} in ${cwd}: timed out`);
        throw new Error(
          `direnv took longer than ${Math.round(budget / 1000)}s in ${cwd}. Run ${warm} in a terminal to warm its cache, then retry.`,
        );
      case "loaded": {
        const { env, unset } = merge(result.env, request.env);
        console.info(
          `direnv: loaded ${cwd} for ${request.reason}: ${Object.keys(result.env)
            .filter((name) => result.env[name] !== null)
            .join(", ")}`,
        );
        if (unset.length > 0) {
          console.debug(
            `direnv: ${cwd} unsets ${unset.join(", ")}; not sent, so the daemon's values stand`,
          );
        }
        return { ...request, env };
      }
    }
  });

  return () => {};
}
