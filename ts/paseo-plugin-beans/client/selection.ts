import { useSyncExternalStore } from "react";

// Module scope is shared by every contribution of one plugin installation, so the
// board and the Explorer panel see the same selection. A reinstall (reload or
// reconnect) evaluates the bundle afresh, which clears it.
const selected = new Map<string, string>();
const listeners = new Set<() => void>();

export function select(workspaceId: string, beanId: string): void {
  if (selected.get(workspaceId) === beanId) return;
  selected.set(workspaceId, beanId);
  for (const listener of listeners) listener();
}

function subscribe(listener: () => void): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

/** The bean selected in this workspace, or null. */
export function useSelection(workspaceId: string): string | null {
  return useSyncExternalStore(subscribe, () => selected.get(workspaceId) ?? null);
}
