import { z } from "zod";

export const SET_STATUS_TOOL = "set_status";

export const statusInputSchema = z.object({
  summary: z
    .string()
    .trim()
    .min(1)
    .max(80)
    .describe("What you are doing right now, in one short line, e.g. \"Fixing the flaky auth test\"."),
  waiting_on: z
    .string()
    .trim()
    .min(1)
    .max(60)
    .optional()
    .describe('What you are blocked on, if anything, e.g. "CI on #1234" or "you: pick a schema".'),
});

export const STATUS_ROW_KIND = "agent-status";
export const STATUS_ROW_VERSION = 1;

/**
 * A row is either the current status or one a later status replaced. Replaced rows stay in
 * the timeline because the daemon can't delete a row, only overwrite it under the same id.
 */
export const statusRowSchema = z.union([
  z.object({ superseded: z.literal(true) }),
  z.object({
    summary: z.string(),
    waitingOn: z.string().optional(),
    setAt: z.number(),
  }),
]);
export type StatusRow = z.output<typeof statusRowSchema>;

/**
 * Providers name MCP tools differently (Claude: `mcp__paseo__set_status`), so this matches
 * any name that ends in the tool name under Paseo's `paseo` MCP server.
 */
export function isSetStatusToolName(name: string): boolean {
  return /(^|[\W_])paseo(__|[./:])set_status$/.test(name);
}
