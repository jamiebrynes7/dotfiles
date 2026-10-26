import type { PluginHandlerContext } from "@getpaseo/plugin/server";
import { matchAuthFailure } from "../shared/detect";

export type Paseo = PluginHandlerContext["paseo"];

/**
 * Resends the message the auth error answered, only when the timeline still ends
 * with exactly that message and then the error. Anything else means the user has
 * moved on, or the turn did work (tool calls, reasoning) that resending would
 * repeat. Resolves whether it sent. `stopped` is checked just before sending, so a
 * plugin stopping mid-refetch sends nothing.
 *
 * The text is the timeline's copy of the message, read back from the provider
 * history: images are lost, and text attachments come back inlined into it.
 */
export async function resendFailedMessage(
  paseo: Paseo,
  agentId: string,
  stopped: () => boolean,
): Promise<boolean> {
  const agent = paseo.agents.ref(agentId);
  const page = await agent.timeline.refetch({ direction: "tail", limit: 2 });
  if (page.error) throw new Error(`could not read the timeline: ${page.error}`);
  const [prompt, reply] = page.entries.slice(-2).map((entry) => entry.item);
  if (prompt?.type !== "user_message" || reply?.type !== "assistant_message") return false;
  if (!matchAuthFailure(reply.text, "complete") || stopped()) return false;
  await agent.send(prompt.text);
  return true;
}
