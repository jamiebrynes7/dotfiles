import { useRpc } from "@getpaseo/plugin/client";
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import { AppState } from "react-native";
import {
  bean as beanRpc,
  board as boardRpc,
  fingerprint as fingerprintRpc,
  type BeanResult,
  type Board,
} from "../shared/rpc.ts";

export const POLL_MS = 10_000;

type Fingerprinted = { kind: "none" } | { kind: "project"; fingerprint: string };

export interface Polled<T> {
  /** The last result loaded, kept through later errors. */
  data: T | null;
  error: string | null;
  refresh(): void;
}

function keyOf(result: Fingerprinted): string {
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
 * Loads on mount, then polls only the fingerprint every 10 s while the app is in the
 * foreground, reloading when it differs from the one the last result was read
 * against. A panel cannot tell whether it is the visible tab, so a hidden-but-mounted
 * tab keeps polling; a fingerprint is only file stats, so that is cheap.
 *
 * `target` names what is loaded (a workspace, or a workspace and bean); a new target
 * starts over. `fetch` may change identity every render.
 */
function usePolled<T extends Fingerprinted>(
  workspaceId: string,
  target: string,
  fetch: () => Promise<T>,
): Polled<T> {
  const callFingerprint = useRpc(fingerprintRpc);
  // The effect below owns the poll for one target; reading the callers through a
  // ref keeps it from restarting if the host hands out new functions per render.
  // Assigned after commit, so a render React discards cannot point a live poll at
  // another target's fetch.
  const rpc = useRef({ callFingerprint, fetch });
  useLayoutEffect(() => {
    rpc.current = { callFingerprint, fetch };
  });
  const [data, setData] = useState<T | null>(null);
  const [error, setError] = useState<string | null>(null);
  const refreshRef = useRef<() => void>(() => {});

  useEffect(() => {
    let live = true;
    let busy = false;
    let forced = false;
    let loadedKey: string | null = null;
    // The fingerprint a failed load ran against. Retrying only once it moves
    // keeps a persistently failing query (a bad config, say) from spawning `beans`
    // every tick; Retry still forces one.
    let failedKey: string | null = null;
    let timer: number | undefined;
    setData(null);
    setError(null);

    async function load(key: string | null = null) {
      let next;
      try {
        next = await rpc.current.fetch();
      } catch (failure) {
        failedKey = key;
        throw failure;
      }
      if (!live) return;
      failedKey = null;
      loadedKey = keyOf(next);
      setData(next);
      setError(null);
    }

    async function check() {
      const current = await rpc.current.callFingerprint({ workspaceId });
      if (!live) return;
      const key = keyOf(current);
      if (key !== loadedKey && key !== failedKey) await load(key);
      // A recovered fingerprint clears its own banner; a load error stands until
      // a load succeeds or the fingerprint moves past the failed one.
      else if (key !== failedKey) setError(null);
    }

    // One request chain at a time, so a slow query cannot stack up behind
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

    // Through the fingerprint even the first time, so a first load that fails is
    // remembered against its fingerprint and not retried every tick.
    run(check);
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
  }, [workspaceId, target]);

  return { data, error, refresh: () => refreshRef.current() };
}

export function useBoard(workspaceId: string): Polled<Board> {
  const callBoard = useRpc(boardRpc);
  return usePolled(workspaceId, workspaceId, () => callBoard({ workspaceId }));
}

export function useBean(workspaceId: string, beanId: string): Polled<BeanResult> {
  const callBean = useRpc(beanRpc);
  return usePolled(workspaceId, `${workspaceId}\0${beanId}`, () =>
    callBean({ workspaceId, beanId }),
  );
}
