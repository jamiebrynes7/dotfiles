import { z } from "zod";

export const WARNING_KIND = "repo-profiles-warning";
// Not 1: version 1 rows carried a single reason, which this schema cannot parse.
export const WARNING_VERSION = 2;

// `field` names the profile field a problem affects; absent when it is about the
// whole profile. `detail` is the path or value the reason is about, drawn as code.
export const WarningProblem = z.object({
  field: z.enum(["skills", "settings"]).optional(),
  reason: z.string(),
  detail: z.string().optional(),
});
export type WarningProblem = z.infer<typeof WarningProblem>;

// `key` is the repository whose profile was matched, when one was.
export const WarningData = z.object({
  problems: z.array(WarningProblem).min(1),
  key: z.string().optional(),
  loaded: z.array(z.enum(["skills", "settings"])),
});
export type WarningData = z.infer<typeof WarningData>;
