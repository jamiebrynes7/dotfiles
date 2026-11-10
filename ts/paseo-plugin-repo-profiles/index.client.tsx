import type { PluginClientContext } from "@getpaseo/plugin/client";
import { WarningCard } from "./client/warning-card.tsx";
import { WARNING_KIND, WARNING_VERSION, WarningData } from "./shared/timeline.ts";

export default function contribute(client: PluginClientContext) {
  return client.addTimelineRenderer({
    kind: WARNING_KIND,
    version: WARNING_VERSION,
    schema: WarningData,
    Component: WarningCard,
  });
}
