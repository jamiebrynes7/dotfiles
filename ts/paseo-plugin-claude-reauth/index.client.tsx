import type { PluginClientContext } from "@getpaseo/plugin/client";
import { AuthCard } from "./client/auth-card";
import { matchAuthFailure } from "./shared/detect";
import { AUTH_EXPIRED_KIND, AuthExpiredData } from "./shared/timeline";

// paseo's Claude provider ignores the SDK's `authentication_failed` marker, so an
// expired login reaches the timeline as plain assistant text and is matched there.
export default function contribute(client: PluginClientContext) {
  const removeTransformer = client.addTimelineTransformer({
    id: AUTH_EXPIRED_KIND,
    query: { itemType: "assistant_message" },
    // Only a finished reply: swapping a streaming one out halfway would lose text.
    transform: ({ item, phase }) => {
      if (phase !== "complete" || !matchAuthFailure(item.text)) return undefined;
      const data: AuthExpiredData = { message: item.text };
      return { items: [{ type: "plugin", kind: AUTH_EXPIRED_KIND, version: 1, data }] };
    },
  });
  const removeRenderer = client.addTimelineRenderer({
    kind: AUTH_EXPIRED_KIND,
    version: 1,
    schema: AuthExpiredData,
    Component: AuthCard,
  });
  return async () => {
    await removeTransformer();
    await removeRenderer();
  };
}
