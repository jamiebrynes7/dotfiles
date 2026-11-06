import type { PluginServerContext } from "@getpaseo/plugin/server";
import { stat } from "node:fs/promises";
import { configPath, readConfig } from "./server/config.ts";
import { listRemoteUrls } from "./server/git.ts";
import { registerHooks } from "./server/hooks.ts";
import { createWarningLedger } from "./server/warnings.ts";

// The returned config is saved with the agent, so resume, reload and daemon restarts
// reuse the stable plugin path set here. A stored agent that never got a provider
// session is re-created instead, and comes back through the hook already carrying it.
export default function contribute(server: PluginServerContext) {
  return registerHooks(server, {
    ledger: createWarningLedger(),
    resolve: (signal) => ({
      readConfig: () => readConfig(configPath()),
      listRemoteUrls: (dir) => listRemoteUrls(dir, { signal }),
      isDirectory: (dir) =>
        stat(dir).then(
          (info) => info.isDirectory(),
          () => false,
        ),
    }),
  });
}
