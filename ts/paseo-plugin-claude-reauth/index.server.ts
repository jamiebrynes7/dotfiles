import type { PluginServerContext } from "@getpaseo/plugin/server";
import { createRecoveries } from "./server/jobs";
import { recoveryStatus, startRecovery } from "./shared/rpc";

// Plugin RPCs time out at 30 s and a browser login routinely takes longer, so both
// handlers answer at once and the card polls. The reload goes through the CLI
// because `refresh_agent_request` is not reachable from the plugin API. The handler's
// `paseo` is the plugin process's own client, so the job may keep using it after the
// handler returns.
export default function contribute(server: PluginServerContext) {
  const recoveries = createRecoveries();
  server.handle(startRecovery, ({ agentId, login }, { paseo }) =>
    recoveries.start(agentId, login, paseo),
  );
  server.handle(recoveryStatus, ({ agentId }) => recoveries.status(agentId));
  return () => recoveries.stop();
}
