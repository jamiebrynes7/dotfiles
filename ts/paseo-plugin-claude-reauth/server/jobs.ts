import { spawn, type ChildProcess } from "node:child_process";
import type { RecoveryState } from "../shared/rpc";

const LOGIN_TIMEOUT_MS = 5 * 60_000;
const RELOAD_TIMEOUT_MS = 2 * 60_000;
const ERROR_TAIL_CHARS = 2_000;
// Only a URL something has followed, so a chunk that ends mid-URL can't record a
// truncated one. ESC is excluded so a colour code after the URL isn't captured.
const URL_PATTERN = /https:\/\/[^\s\x1b]+(?=[\s\x1b])/;

export interface Recoveries {
  start(agentId: string, login: boolean): RecoveryState;
  status(agentId: string): RecoveryState;
  /** Kills every running child; later results are dropped. */
  stop(): void;
}

interface LoginJob {
  done: Promise<void>;
  url?: string;
}

function isRunning(state: RecoveryState): boolean {
  return state.phase === "logging-in" || state.phase === "reloading";
}

function tail(text: string): string {
  return text.trim().slice(-ERROR_TAIL_CHARS);
}

// The SDK's terminateProcess signals only the direct child on POSIX, which leaves a
// wrapper script's descendants running and holding the output pipes open. Each child
// leads its own process group instead, so the whole tree goes.
function kill(child: ChildProcess) {
  if (child.pid === undefined) return;
  try {
    process.kill(-child.pid, "SIGKILL");
  } catch {
    // Already exited.
  }
}

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function createRecoveries(): Recoveries {
  const states = new Map<string, RecoveryState>();
  const children = new Set<ChildProcess>();
  let login: LoginJob | undefined;
  let stopped = false;

  function set(agentId: string, state: RecoveryState) {
    if (!stopped) states.set(agentId, state);
  }

  // Resolves on exit 0. Rejects with the stderr tail, the spawn error (ENOENT when
  // the binary is not on the daemon's PATH), or `timeoutMessage`. `onOutput` gets
  // each stream's recent output, kept apart so interleaved writes can't merge.
  function run(
    command: string,
    args: string[],
    options: { timeoutMs: number; timeoutMessage: string; onOutput?: (recent: string) => void },
  ): Promise<void> {
    if (stopped) return Promise.reject(new Error("claude-reauth is stopping"));
    return new Promise((resolve, reject) => {
      const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"], detached: true });
      children.add(child);
      const output = { stdout: "", stderr: "" };
      let settled = false;
      // Settled here rather than on `close`: a descendant outside the group that
      // still holds the pipes would otherwise keep the job, and the shared login,
      // running forever.
      const timer = setTimeout(() => {
        kill(child);
        settle(new Error(options.timeoutMessage));
      }, options.timeoutMs);

      function settle(error?: Error) {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        children.delete(child);
        if (error) reject(error);
        else resolve();
      }

      for (const stream of ["stdout", "stderr"] as const) {
        child[stream]?.on("data", (chunk: Buffer) => {
          output[stream] = (output[stream] + chunk.toString()).slice(-ERROR_TAIL_CHARS);
          options.onOutput?.(output[stream]);
        });
      }
      child.on("error", (error) => settle(error));
      child.on("close", (code, signal) => {
        if (code === 0) settle();
        else settle(new Error(tail(output.stderr) || `${command} exited with ${code ?? signal}`));
      });
    });
  }

  function sharedLogin(): LoginJob {
    if (login) return login;
    const job: LoginJob = {
      done: run("claude", ["auth", "login"], {
        timeoutMs: LOGIN_TIMEOUT_MS,
        timeoutMessage: "login timed out",
        onOutput(recent) {
          if (job.url) return;
          const url = recent.match(URL_PATTERN)?.[0];
          if (!url) return;
          job.url = url;
          for (const [agentId, state] of states) {
            if (state.phase === "logging-in") set(agentId, { phase: "logging-in", url });
          }
        },
      }).finally(() => {
        login = undefined;
      }),
    };
    login = job;
    return job;
  }

  function reload(agentId: string) {
    set(agentId, { phase: "reloading" });
    run("paseo", ["agent", "reload", agentId], {
      timeoutMs: RELOAD_TIMEOUT_MS,
      timeoutMessage: "reload timed out",
    }).then(
      () => set(agentId, { phase: "done" }),
      (error: unknown) => set(agentId, { phase: "failed", step: "reload", error: messageOf(error) }),
    );
  }

  function status(agentId: string): RecoveryState {
    return states.get(agentId) ?? { phase: "idle" };
  }

  return {
    status,
    start(agentId, withLogin) {
      const current = status(agentId);
      if (stopped || isRunning(current)) return current;
      if (!withLogin) {
        reload(agentId);
        return status(agentId);
      }
      const job = sharedLogin();
      set(agentId, { phase: "logging-in", ...(job.url ? { url: job.url } : {}) });
      job.done.then(
        () => reload(agentId),
        (error: unknown) =>
          set(agentId, {
            phase: "failed",
            step: "login",
            error: messageOf(error),
            ...(job.url ? { url: job.url } : {}),
          }),
      );
      return status(agentId);
    },
    stop() {
      stopped = true;
      for (const child of children) kill(child);
    },
  };
}
