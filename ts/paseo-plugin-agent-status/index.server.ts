import { defineAgentTool, type PluginServerContext } from "@getpaseo/plugin/server";
import { createStatusRows } from "./server/status-rows.ts";
import { SET_STATUS_TOOL, statusInputSchema } from "./shared/status.ts";

const DESCRIPTION = `Set the status shown at the bottom of your chat, so the user can tell at a glance what you are doing and what you are waiting on when they come back to you among many parallel agents. It appears when your turn ends.

Call it when you start a task, whenever your phase changes, and always before you end a turn, even if the status is unchanged.

- summary: the task and where it stands, e.g. "Fixing the flaky auth test" or "Auth test fixed, all tests pass". Don't repeat what you are blocked on here; that goes in waiting_on. At most 80 characters.
- waiting_on: set whenever you are blocked, e.g. "CI on #1234". Use "you" (optionally with what you need, e.g. "you: pick raise or clamp") when you need the user's input or have finished. Omit it while you are working. At most 60 characters.`;

export default function contribute(server: PluginServerContext) {
  const rows = createStatusRows();

  const setStatus = defineAgentTool({
    name: SET_STATUS_TOOL,
    title: "Set status",
    description: DESCRIPTION,
    input: statusInputSchema,
    execute(input, { agent }) {
      rows.record(agent.id, {
        summary: input.summary,
        ...(input.waiting_on ? { waitingOn: input.waiting_on } : {}),
        setAt: Date.now(),
      });
      return { text: "Status updated." };
    },
  });

  const removeOpenHook = server.addHook("agent.open.before", async ({ request }) => {
    if (request.purpose !== "interactive") return request;
    return { ...request, tools: [...request.tools, setStatus] };
  });
  // Every outcome counts: a cancelled or failed turn still leaves the agent idle with
  // its last status worth showing.
  const removeTurnHook = server.addHook("agent.turn.after", async ({ agent }, { paseo }) => {
    await rows.showAtBottom(paseo, agent.id);
  });
  return () => {
    removeOpenHook();
    removeTurnHook();
  };
}
