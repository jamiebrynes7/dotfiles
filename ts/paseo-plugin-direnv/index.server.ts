import type { PluginServerContext } from "@getpaseo/plugin/server";
import path from "node:path";
import { evaluate, TIMEOUT_MS } from "./server/evaluate";
import { merge } from "./server/merge";

// Single-quoted so a suggested command survives copy-paste for a path with spaces.
function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'\\''`)}'`;
}

// Every open re-evaluates and nothing is cached: env overrides are not persisted, so
// each create, resume, refresh and import comes through here, and an `.envrc` edited
// since it was allowed is refused at the next open instead of running stale.
// Logs carry outcomes, directories and variable names, never values.
export default function contribute(server: PluginServerContext) {
  let reportedUnavailable = false;

  server.before("agent.session_open", async ({ request }, { signal }) => {
    // An archived agent opened to read its timeline; its directory may be gone.
    if (request.purpose === "history") return;

    const { cwd } = request;
    const warm = `\`direnv exec ${shellQuote(cwd)} true\``;
    const result = await evaluate(cwd, signal);
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
          `direnv took longer than ${TIMEOUT_MS / 1000}s in ${cwd}. Run ${warm} in a terminal to warm its cache, then retry.`,
        );
      case "loaded": {
        const { env, unset } = merge(result.env, request.env);
        console.info(
          `direnv: loaded ${cwd} for ${request.reason}: ${Object.keys(result.env)
            .filter((name) => result.env[name] !== null)
            .join(", ")}`,
        );
        if (unset.length > 0) {
          console.debug(`direnv: ${cwd} unsets ${unset.join(", ")}; not sent, so the daemon's values stand`);
        }
        return { ...request, env };
      }
    }
  });

  return () => {};
}
