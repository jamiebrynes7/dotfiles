import type { PluginServerContext } from "@getpaseo/plugin/server";
import { stat } from "node:fs/promises";
import { configPath, readConfig } from "./server/config.ts";
import { listRemoteUrls } from "./server/git.ts";
import { decide, withPluginDir } from "./server/resolve.ts";

// The returned config is saved with the agent, so this runs once per agent: resume,
// reload and daemon restarts reuse the stable plugin path set here. Every failure
// returns the request unchanged, because a throw would fail agent creation.
export default function contribute(server: PluginServerContext) {
  server.addHook("agent.create.before", async ({ request }, { signal }) => {
    const { cwd } = request.config;
    try {
      const decision = await decide(request.config, {
        readConfig: () => readConfig(configPath()),
        listRemoteUrls: (dir) => listRemoteUrls(dir, { signal }),
        isDirectory: (dir) => stat(dir).then((info) => info.isDirectory(), () => false),
      });
      switch (decision.kind) {
        case "unchanged":
          return;
        case "skipped":
          console.warn(`repo-skills: not loading skills in ${cwd}: ${decision.reason}`);
          return;
        case "load":
          console.info(`repo-skills: loading ${decision.key} skills in ${cwd}`);
          if (decision.alsoMatched.length > 0) {
            console.warn(
              `repo-skills: ${cwd} also matches ${decision.alsoMatched.join(", ")}; only ${decision.key} is loaded`,
            );
          }
          return { ...request, config: withPluginDir(request.config, decision.pluginDir) };
      }
    } catch (error) {
      console.warn(
        `repo-skills: not loading skills in ${cwd}: ${error instanceof Error ? error.message : error}`,
      );
      return;
    }
  });

  return () => {};
}
