import { defineAgentTool, type PluginServerContext } from "@getpaseo/plugin/server";
import { createStatusRows } from "./server/status-rows.ts";
import { SET_STATUS_TOOL, statusInputSchema } from "./shared/status.ts";

const DESCRIPTION = `Set the one-line status shown at the bottom of your chat, so the user can tell at a glance what you are doing and what you are waiting on when they come back to you among many parallel agents.

Call it when you start a task, whenever your phase changes, and always before you end a turn, even if the status is unchanged.

- summary: what you are doing now, e.g. "Fixing the flaky auth test". At most 80 characters.
- waiting_on: set whenever you are blocked, e.g. "CI on #1234". Use "you" (optionally with what you need, e.g. "you: pick a schema") when you need the user's input or have finished. At most 60 characters.`;

export default function contribute(server: PluginServerContext) {
  const rows = createStatusRows();

  const setStatus = defineAgentTool({
    name: SET_STATUS_TOOL,
    title: "Set status",
    description: DESCRIPTION,
    input: statusInputSchema,
    async execute(input, { agent, paseo }) {
      await rows.publish(paseo, agent.id, {
        summary: input.summary,
        ...(input.waiting_on ? { waitingOn: input.waiting_on } : {}),
        setAt: Date.now(),
      });
      return { text: "Status updated." };
    },
  });

  return server.addHook("agent.open.before", async ({ request }) => {
    if (request.purpose !== "interactive") return request;
    return { ...request, tools: [...request.tools, setStatus] };
  });
}
