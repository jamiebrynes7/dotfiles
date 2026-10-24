import type { PluginButtonRegistration, PluginClientContext } from "@getpaseo/plugin/client";

interface WorkspaceEntry {
  id: string;
  archivingAt?: string | null;
}

// The daemon removes a terminal the moment its process exits, which would take
// direnv's output with it. So the command runs under `sh`, reports its exit
// status, and hands over to an interactive shell that keeps the terminal open.
const KEEP_OPEN =
  'direnv "$@"; status=$?; printf "\\n[direnv exited %s]\\n" "$status"; exec "${SHELL:-/bin/sh}" -i';

const RESUBSCRIBE_MS = 10_000;

// One `direnv` menu per workspace, with no per-workspace `.envrc` detection: that
// would need an RPC and keeping it fresh. Both items open a terminal tab in the
// workspace directory (the worktree for worktrees), which only needs
// `workspace.write`; a failure to open one surfaces as paseo's error toast. The app
// adds plugin-opened terminals without focusing them, so the tab name is the cue.
export default function contribute(client: PluginClientContext) {
  const buttons = new Map<string, PluginButtonRegistration>();
  let release: (() => Promise<void>) | undefined;
  let retryTimer: number | undefined;
  let stopped = false;

  function openTerminal(workspaceId: string, name: string, args: string[]) {
    return client.paseo.workspaces
      .ref(workspaceId)
      .terminals.create({ name, command: "sh", args: ["-c", KEEP_OPEN, "sh", ...args] })
      .then(() => undefined);
  }

  function add(workspaceId: string) {
    if (stopped || buttons.has(workspaceId)) return;
    buttons.set(
      workspaceId,
      client.addHeaderButton({
        id: "direnv",
        workspaceId,
        button: {
          title: "direnv",
          icon: "SquareTerminal",
          behavior: {
            kind: "menu",
            items: [
              {
                kind: "item",
                id: "allow",
                title: "Allow",
                icon: "ShieldCheck",
                // Pressing it is the deliberate act of trust; no extra review step.
                behavior: {
                  kind: "action",
                  onPress: () => openTerminal(workspaceId, "direnv allow", ["allow"]),
                },
              },
              {
                kind: "item",
                id: "warm",
                title: "Warm",
                icon: "Flame",
                // No time limit and visible output, so a cold devshell is built and
                // cached outside the launch hook's budget.
                behavior: {
                  kind: "action",
                  onPress: () => openTerminal(workspaceId, "direnv warm", ["exec", ".", "true"]),
                },
              },
            ],
          },
        },
      }),
    );
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
      console.error("direnv: could not release the workspace subscription", error);
    });
  }

  // A failed re-subscribe after a reconnect releases the subscription, so observation
  // would otherwise stop for good: new workspaces would get no button.
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
        // Stopped while the list was in flight: nothing else would release it.
        if (stopped) {
          releaseSubscription();
          return;
        }
        subscription.subscribe({
          // Initial load and every reconnect: workspaces may have come and gone. A
          // snapshot is the first 200 workspaces (the daemon's default page), far
          // beyond a personal setup.
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
            console.error("direnv: workspace observation failed; retrying", error);
            release = undefined;
            retryLater();
          },
        });
      })
      .catch((error: unknown) => {
        if (stopped) return;
        console.error("direnv: workspace observation failed; retrying", error);
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
