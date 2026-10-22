import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

export const RecoveryState = z.discriminatedUnion("phase", [
  z.object({ phase: z.literal("idle") }),
  z.object({ phase: z.literal("logging-in"), url: z.string().optional() }),
  z.object({ phase: z.literal("reloading") }),
  z.object({ phase: z.literal("done") }),
  z.object({
    phase: z.literal("failed"),
    step: z.enum(["login", "reload"]),
    error: z.string(),
    url: z.string().optional(),
  }),
]);
export type RecoveryState = z.infer<typeof RecoveryState>;

// A GUID, as upstream's AgentIdSchema: the id lands in `paseo agent reload`'s argv,
// whose resolver also accepts prefixes and titles, and a leading `-` reads as an option.
const AgentId = z.guid();

/** Kicks off a recovery for one agent and returns at once; a no-op while one runs. */
export const startRecovery = defineRpc({
  name: "claude-reauth.start",
  input: z.object({ agentId: AgentId, login: z.boolean() }),
  output: RecoveryState,
});

/** The agent's current recovery state; "idle" if none was ever started. */
export const recoveryStatus = defineRpc({
  name: "claude-reauth.status",
  input: z.object({ agentId: AgentId }),
  output: RecoveryState,
});
