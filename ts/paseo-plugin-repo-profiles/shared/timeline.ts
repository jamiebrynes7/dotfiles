import { z } from "zod";

export const WARNING_KIND = "repo-profiles-warning";
export const WARNING_VERSION = 1;

// `detail` is the path or value the reason is about, drawn as code on its own line.
// `loaded` is set when one repository's skills did load and the warning is about the
// others (remotes matching several keys); otherwise none were loaded.
export const WarningData = z.object({
  reason: z.string(),
  detail: z.string().optional(),
  loaded: z.string().optional(),
});
export type WarningData = z.infer<typeof WarningData>;
