import type { PluginClientContext } from "@getpaseo/plugin/client";
import { StatusCardView } from "./client/status-card.tsx";
import { isSetStatusToolName, STATUS_ROW_KIND, STATUS_ROW_VERSION, statusRowSchema } from "./shared/status.ts";

export default function contribute(client: PluginClientContext) {
  const removeRenderer = client.addTimelineRenderer({
    kind: STATUS_ROW_KIND,
    version: STATUS_ROW_VERSION,
    schema: statusRowSchema,
    Component: StatusCardView,
  });
  // The status row already shows what the call said, so the call itself is noise.
  const removeTransformer = client.addTimelineTransformer({
    id: "hide-set-status-calls",
    query: { itemType: "tool_call" },
    transform: ({ item }) => (isSetStatusToolName(item.name) ? { items: [] } : undefined),
  });
  return () => {
    removeRenderer();
    removeTransformer();
  };
}
