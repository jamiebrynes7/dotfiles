import { z } from "zod";

export const LINK_KINDS = ["pr", "review", "other"] as const;
export const MAX_LINKS = 3;

const linkInputSchema = z.object({
  kind: z.enum(LINK_KINDS).describe('"pr" for a pull request, "review" for a review page (e.g. Plannotator), "other" for anything else.'),
  url: z.url({ protocol: /^https?$/ }).trim().max(500).describe("An http(s) URL."),
});

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
  links: z
    .array(linkInputSchema)
    .min(1)
    .max(MAX_LINKS)
    .optional()
    .describe("Links worth opening for this task, such as its pull request or a review awaiting the user."),
});

export const STATUS_ROW_KIND = "agent-status";
export const STATUS_ROW_VERSION = 1;

/** `kind` is a plain string here so a client older than a new kind still renders the row. */
export const statusLinkSchema = z.object({ kind: z.string(), url: z.string() });
export type StatusLink = z.output<typeof statusLinkSchema>;

/**
 * A row is either the current status or one a later status replaced. Replaced rows stay in
 * the timeline because the daemon can't delete a row, only overwrite it under the same id.
 */
export const statusRowSchema = z.union([
  z.object({ superseded: z.literal(true) }),
  z.object({
    summary: z.string(),
    waitingOn: z.string().optional(),
    links: z.array(statusLinkSchema).optional(),
    setAt: z.number(),
  }),
]);
export type StatusRow = z.output<typeof statusRowSchema>;
