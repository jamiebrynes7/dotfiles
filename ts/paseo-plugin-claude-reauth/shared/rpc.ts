import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

export const RecoveryState = z.discriminatedUnion("phase", [
  z.object({ phase: z.literal("idle") }),
  z.object({ phase: z.literal("logging-in"), url: z.string().optional() }),
  z.object({ phase: z.literal("reloading") }),
  z.object({ phase: z.literal("resending") }),
  // `at` on a settled phase is when the run ended, so a card that appeared later can
  // tell the run was for an earlier auth error.
  z.object({ phase: z.literal("done"), at: z.iso.datetime(), resent: z.boolean() }),
  z.object({
    phase: z.literal("failed"),
    step: z.enum(["login", "reload", "resend"]),
    error: z.string(),
    url: z.string().optional(),
    at: z.iso.datetime(),
  }),
]);
export type RecoveryState = z.infer<typeof RecoveryState>;

/**
 * `lastDoneAt` is when the agent's latest successful recovery ended. It outlives the
 * `done` state, so a card older than it stays spent while a later run is going or
 * after it fails.
 */
export const Recovery = z.object({
  state: RecoveryState,
  lastDoneAt: z.iso.datetime().optional(),
});
export type Recovery = z.infer<typeof Recovery>;

// A GUID, as upstream's AgentIdSchema: the id lands in `paseo agent reload`'s argv,
// whose resolver also accepts prefixes and titles, and a leading `-` reads as an option.
const AgentId = z.guid();

/** Kicks off a recovery for one agent and returns at once; a no-op while one runs. */
export const startRecovery = defineRpc({
  name: "claude-reauth.start",
  input: z.object({ agentId: AgentId, login: z.boolean() }),
  output: Recovery,
});

/** The agent's current recovery state; "idle" if none was ever started. */
export const recoveryStatus = defineRpc({
  name: "claude-reauth.status",
  input: z.object({ agentId: AgentId }),
  output: Recovery,
});
