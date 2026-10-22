import type { PluginServerContext } from "@getpaseo/plugin/server";
import { createRecoveries } from "./server/jobs";
import { recoveryStatus, startRecovery } from "./shared/rpc";

// Plugin RPCs time out at 30 s and a browser login routinely takes longer, so both
// handlers answer at once and the card polls. The reload goes through the CLI
// because `refresh_agent_request` is not reachable from the plugin API.
export default function contribute(server: PluginServerContext) {
  const recoveries = createRecoveries();
  server.handle(startRecovery, ({ agentId, login }) => recoveries.start(agentId, login));
  server.handle(recoveryStatus, ({ agentId }) => recoveries.status(agentId));
  return () => recoveries.stop();
}
