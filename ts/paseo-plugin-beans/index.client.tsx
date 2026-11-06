import type { PluginButtonRegistration, PluginClientContext } from "@getpaseo/plugin/client";
import { BoardPanel } from "./client/board-panel.tsx";

const BOARD_PANEL = "beans-board";
const ICON = "SquareKanban";
const RESUBSCRIBE_MS = 10_000;

interface WorkspaceEntry {
  id: string;
  archivingAt?: string | null;
}

export default function contribute(client: PluginClientContext) {
  const removePanel = client.addWorkspacePanel({
    id: BOARD_PANEL,
    title: "Beans",
    icon: ICON,
    Component: BoardPanel,
  });
  const removeCommand = client.addCommandCenterItem({
    id: "open-board",
    title: "Open beans board",
    icon: ICON,
    keywords: ["beans", "kanban", "board", "issues"],
    context: "workspace",
    onSelect: ({ openPanel }) => openPanel(BOARD_PANEL),
  });
  const stopButtons = observeWorkspaces(client, (workspaceId) =>
    client.addHeaderButton({
      id: "beans",
      workspaceId,
      button: {
        title: "Beans board",
        icon: ICON,
        behavior: {
          kind: "action",
          onPress: () => client.openPanel(BOARD_PANEL, { workspaceId }),
        },
      },
    }),
  );

  return async () => {
    stopButtons();
    await removeCommand();
    await removePanel();
  };
}

// Header buttons are per workspace, so they follow the daemon's workspace list. The
// same observer as ts/paseo-plugin-direnv's (plugins ship as standalone copies), so
// a fix to one belongs in both. A
// failed re-subscribe after a reconnect releases the subscription, so it is retried,
// or new workspaces would get no button.
function observeWorkspaces(
  client: PluginClientContext,
  addButton: (workspaceId: string) => PluginButtonRegistration,
): () => void {
  const buttons = new Map<string, PluginButtonRegistration>();
  let release: (() => Promise<void>) | undefined;
  let retryTimer: number | undefined;
  let stopped = false;

  function add(workspaceId: string) {
    if (stopped || buttons.has(workspaceId)) return;
    buttons.set(workspaceId, addButton(workspaceId));
  }

  function remove(workspaceId: string) {
    buttons.get(workspaceId)?.remove();
    buttons.delete(workspaceId);
  }

  function track(workspace: WorkspaceEntry) {
    if (workspace.archivingAt) remove(workspace.id);
    else add(workspace.id);
  }

  function releaseSubscription() {
    const current = release;
    release = undefined;
    current?.().catch((error: unknown) => {
      console.error("beans: could not release the workspace subscription", error);
    });
  }

  function retryLater() {
    if (stopped) return;
    clearTimeout(retryTimer);
    retryTimer = setTimeout(observe, RESUBSCRIBE_MS);
  }

  function observe() {
    if (stopped) return;
    client.paseo.workspaces
      .list({ subscribe: {} })
      .then(({ subscription }) => {
        release = () => subscription.release();
        if (stopped) {
          releaseSubscription();
          return;
        }
        subscription.subscribe({
          // Initial load and every reconnect: workspaces may have come and gone.
          snapshot: ({ entries }) => {
            const present = new Set(entries.map((workspace) => workspace.id));
            for (const id of [...buttons.keys()]) if (!present.has(id)) remove(id);
            for (const workspace of entries) track(workspace);
          },
          update: (message) => {
            if (message.type !== "workspace_update") return;
            const update = message.payload;
            if (update.kind === "remove") remove(update.id);
            else track(update.workspace);
          },
          error: (error) => {
            console.error("beans: workspace observation failed; retrying", error);
            release = undefined;
            retryLater();
          },
        });
      })
      .catch((error: unknown) => {
        if (stopped) return;
        console.error("beans: workspace observation failed; retrying", error);
        retryLater();
      });
  }

  observe();

  return () => {
    stopped = true;
    clearTimeout(retryTimer);
    releaseSubscription();
    for (const id of [...buttons.keys()]) remove(id);
  };
}
