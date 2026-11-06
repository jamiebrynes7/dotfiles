import { useRpc } from "@getpaseo/plugin/client";
import { useEffect, useRef, useState } from "react";
import { AppState } from "react-native";
import { board as boardRpc, fingerprint as fingerprintRpc, type Board } from "../shared/rpc.ts";

export const POLL_MS = 10_000;

export interface BoardState {
  /** The last board loaded, kept through later errors. */
  board: Board | null;
  error: string | null;
  refresh(): void;
}

function keyOf(result: { kind: "none" } | { kind: "project"; fingerprint: string }): string {
  return result.kind === "none" ? "none" : `project:${result.fingerprint}`;
}

// Web can report "unknown" before its first change event; only an explicit
// background state pauses the poll.
function foreground(state: string): boolean {
  return state !== "background" && state !== "inactive";
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/**
 * Loads the board on mount, then polls only the fingerprint every 10 s while the app
 * is in the foreground, refetching the board when it differs from the one loaded.
 * A panel cannot tell whether it is the visible tab, so a hidden-but-mounted tab
 * keeps polling; a fingerprint is only file stats, so that is cheap.
 */
export function useBoard(workspaceId: string): BoardState {
  const callFingerprint = useRpc(fingerprintRpc);
  const callBoard = useRpc(boardRpc);
  // The effect below owns the poll for one workspace; reading the callers through a
  // ref keeps it from restarting if the host hands out new functions per render.
  const rpc = useRef({ callFingerprint, callBoard });
  rpc.current = { callFingerprint, callBoard };
  const [board, setBoard] = useState<Board | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refreshRef = useRef<() => void>(() => {});

  useEffect(() => {
    let live = true;
    let busy = false;
    let forced = false;
    let loadedKey: string | null = null;
    // The fingerprint a failed board load ran against. Retrying only once it moves
    // keeps a persistently failing query (a bad config, say) from spawning `beans`
    // every tick; Retry still forces one.
    let failedKey: string | null = null;
    let timer: number | undefined;
    setBoard(null);
    setError(null);

    async function load(key: string | null = null) {
      let next;
      try {
        next = await rpc.current.callBoard({ workspaceId });
      } catch (failure) {
        failedKey = key;
        throw failure;
      }
      if (!live) return;
      failedKey = null;
      loadedKey = keyOf(next);
      setBoard(next);
      setError(null);
    }

    async function check() {
      const current = await rpc.current.callFingerprint({ workspaceId });
      if (!live) return;
      const key = keyOf(current);
      if (key !== loadedKey && key !== failedKey) await load(key);
      // A recovered fingerprint clears its own banner; a load error stands until
      // the board loads or the fingerprint moves past the failed one.
      else if (key !== failedKey) setError(null);
    }

    // One request chain at a time, so a slow board query cannot stack up behind
    // ticks. A refresh pressed meanwhile runs as soon as the chain ends.
    function run(work: () => Promise<void>) {
      if (busy) return;
      busy = true;
      work()
        .catch((failure: unknown) => {
          if (live) setError(message(failure));
        })
        .finally(() => {
          busy = false;
          if (live && forced) {
            forced = false;
            run(() => load());
          }
        });
    }

    const tick = () => run(check);
    refreshRef.current = () => {
      if (busy) forced = true;
      else run(() => load());
    };
    const start = () => {
      if (timer === undefined) timer = setInterval(tick, POLL_MS);
    };
    const stop = () => {
      if (timer !== undefined) clearInterval(timer);
      timer = undefined;
    };

    run(() => load());
    if (foreground(AppState.currentState)) start();
    const subscription = AppState.addEventListener("change", (state) => {
      if (foreground(state)) {
        tick();
        start();
      } else {
        stop();
      }
    });
    return () => {
      live = false;
      stop();
      subscription.remove();
      refreshRef.current = () => {};
    };
  }, [workspaceId]);

  return { board, error, refresh: () => refreshRef.current() };
}
