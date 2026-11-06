import { stat } from "node:fs/promises";
import { z } from "zod";
import type { Board, Fingerprint } from "../shared/rpc.ts";
import { graphql, type CliOptions } from "./cli.ts";
import { findProject, fingerprintOf } from "./project.ts";

// `isBlocked` covers explicit blockers and a blocked ancestor alike, which is what
// the card's marker means.
const BOARD_QUERY = `{
  beans { id slug title status implicitStatus type priority parentId updatedAt tags }
  blocked: beans(filter: { isBlocked: true }) { id }
}`;

const BoardResponse = z.object({
  beans: z.array(
    z.object({
      id: z.string(),
      slug: z.string().nullable(),
      title: z.string(),
      status: z.string(),
      implicitStatus: z.string().nullable(),
      type: z.string(),
      priority: z.string().nullable(),
      parentId: z.string().nullable(),
      updatedAt: z.string(),
      tags: z.array(z.string()),
    }),
  ),
  blocked: z.array(z.object({ id: z.string() })),
});

export async function readFingerprint(directory: string): Promise<Fingerprint> {
  const project = await findProject(directory);
  if (!project) return { kind: "none", directory };
  return { kind: "project", fingerprint: await fingerprintOf(project) };
}

// The fingerprint is taken before the query, so a change landing mid-query shows up
// as a mismatch on the next poll instead of being lost.
export async function readBoard(directory: string, options: CliOptions = {}): Promise<Board> {
  const project = await findProject(directory);
  if (!project) return { kind: "none", directory };
  const fingerprint = await fingerprintOf(project);
  // The CLI refuses a missing data directory, which a fresh checkout of a project
  // with no beans has (git tracks no empty directories): that is an empty board.
  const hasData = await stat(project.dataDir).then(
    () => true,
    (error: NodeJS.ErrnoException) => {
      if (error.code === "ENOENT") return false;
      throw error;
    },
  );
  if (!hasData) return { kind: "project", fingerprint, beans: [] };
  const parsed = BoardResponse.safeParse(await graphql(directory, BOARD_QUERY, {}, options));
  if (!parsed.success) {
    throw new Error(`beans returned an unexpected board shape: ${z.prettifyError(parsed.error)}`);
  }
  const blocked = new Set(parsed.data.blocked.map((bean) => bean.id));
  return {
    kind: "project",
    fingerprint,
    beans: parsed.data.beans.map((bean) => ({
      ...bean,
      priority: bean.priority ?? "normal",
      blocked: blocked.has(bean.id),
    })),
  };
}
