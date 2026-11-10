import type { PluginHandlerContext, PluginServerContext } from "@getpaseo/plugin/server";
import { readBean, readBoard, readFingerprint } from "./server/board.ts";
import { bean, board, fingerprint } from "./shared/rpc.ts";

// The workspace's own directory, so a worktree shows its branch's beans. Resolved
// per call rather than cached: the daemon is the source of truth for the mapping.
async function directoryOf(paseo: PluginHandlerContext["paseo"], workspaceId: string): Promise<string> {
  const workspace = await paseo.workspaces.ref(workspaceId).refresh();
  if (!workspace) throw new Error(`Unknown workspace ${workspaceId}`);
  if (!workspace.workspaceDirectory) throw new Error(`Workspace ${workspaceId} has no directory`);
  return workspace.workspaceDirectory;
}

// No caching here: the client compares fingerprints, and refetches only on a change.
export default function contribute(server: PluginServerContext) {
  server.handle(fingerprint, async ({ workspaceId }, { paseo }) =>
    readFingerprint(await directoryOf(paseo, workspaceId)),
  );
  server.handle(board, async ({ workspaceId, search }, { paseo }) =>
    readBoard(await directoryOf(paseo, workspaceId), search ?? null),
  );
  server.handle(bean, async ({ workspaceId, beanId }, { paseo }) =>
    readBean(await directoryOf(paseo, workspaceId), beanId),
  );
  return () => {};
}
