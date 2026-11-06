import { defineRpc } from "@getpaseo/plugin";
import { z } from "zod";

// A workspace id, never a path: the server resolves the directory itself, so a
// client cannot point the CLI anywhere else.
const WorkspaceInput = z.object({ workspaceId: z.string().min(1) });

export const BoardBean = z.object({
  id: z.string(),
  slug: z.string().nullable(),
  title: z.string(),
  status: z.string(),
  /** A terminal status inherited from a completed or scrapped ancestor. */
  implicitStatus: z.string().nullable(),
  type: z.string(),
  priority: z.string(),
  parentId: z.string().nullable(),
  updatedAt: z.string(),
  tags: z.array(z.string()),
  blocked: z.boolean(),
});
export type BoardBean = z.infer<typeof BoardBean>;

const NoProject = z.object({ kind: z.literal("none"), directory: z.string() });

export const Fingerprint = z.discriminatedUnion("kind", [
  NoProject,
  z.object({ kind: z.literal("project"), fingerprint: z.string() }),
]);
export type Fingerprint = z.infer<typeof Fingerprint>;

export const Board = z.discriminatedUnion("kind", [
  NoProject,
  z.object({ kind: z.literal("project"), fingerprint: z.string(), beans: z.array(BoardBean) }),
]);
export type Board = z.infer<typeof Board>;

/** File stats only, no `beans` process: the poll's cheap "has anything changed?" check. */
export const fingerprint = defineRpc({
  name: "beans.fingerprint",
  input: WorkspaceInput,
  output: Fingerprint,
});

/** Every bean of the project, with the fingerprint taken just before the query. */
export const board = defineRpc({
  name: "beans.board",
  input: WorkspaceInput,
  output: Board,
});
