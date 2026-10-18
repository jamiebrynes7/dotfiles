import { spawn, type ChildProcess } from "node:child_process";
import { stat } from "node:fs/promises";
import type { Readable } from "node:stream";

// Under the daemon's fixed 30 s hook limit, so a slow `.envrc` gets this plugin's
// message rather than the generic `Plugin RPC timed out`.
export const TIMEOUT_MS = 25_000;
const STDERR_TAIL_LINES = 8;
const STDERR_KEEP_BYTES = 64 * 1024;
// How long to wait for the last of stderr once direnv has exited. A process the
// `.envrc` backgrounded inherits stderr and can hold it open indefinitely.
const STDERR_DRAIN_MS = 200;

export type DirenvEnv = Record<string, string | null>;

export type Evaluation =
  | { kind: "unavailable" }
  | { kind: "none" }
  | { kind: "loaded"; env: DirenvEnv }
  | { kind: "blocked"; envrc: string }
  | { kind: "failed"; exit: string; stderrTail: string }
  | { kind: "timeout" };

type Outcome =
  | { kind: "exited"; code: number | null; signal: NodeJS.Signals | null }
  | { kind: "error"; error: NodeJS.ErrnoException }
  | { kind: "aborted" };

// Covers CSI sequences (direnv's colours) and the two-byte escapes.
const ANSI = /\x1b(?:\[[0-?]*[ -/]*[@-~]|[@-Z\\-_])/g;

function stripAnsi(text: string): string {
  return text.replace(ANSI, "");
}

function tail(stderr: string): string {
  const lines = stripAnsi(stderr)
    .split("\n")
    .map((line) => line.trimEnd())
    .filter((line) => line.trim() !== "");
  return lines.slice(-STDERR_TAIL_LINES).join("\n");
}

// direnv: error /path/.envrc is blocked. Run `direnv allow` to approve its content
const BLOCKED = /error (.+?) is blocked\./;

// Runs `direnv export json` in `cwd` with the plugin's own environment, which is the
// daemon's (plugin children are forked without an `env`). The hook's request env is
// only an overlay, so it would leave direnv without PATH or HOME.
export async function evaluate(cwd: string, signal: AbortSignal): Promise<Evaluation> {
  const abort = AbortSignal.any([signal, AbortSignal.timeout(TIMEOUT_MS)]);
  // Its own process group, so a timeout also stops the `.envrc`'s bash and any nix
  // evaluation under it rather than orphaning them.
  const child = spawn("direnv", ["export", "json"], {
    cwd,
    env: process.env,
    stdio: ["ignore", "pipe", "pipe"],
    detached: true,
  });

  let stdout = "";
  let stderr = "";
  child.stdout.setEncoding("utf8").on("data", (chunk: string) => (stdout += chunk));
  child.stderr.setEncoding("utf8").on("data", (chunk: string) => {
    stderr = (stderr + chunk).slice(-STDERR_KEEP_BYTES);
  });

  const outcome = await run(child, abort);
  child.stdout.destroy();
  child.stderr.destroy();

  if (outcome.kind === "aborted") return { kind: "timeout" };
  if (outcome.kind === "error") {
    if (outcome.error.code !== "ENOENT") throw outcome.error;
    // spawn reports a missing cwd as ENOENT too. A missing directory is not direnv's
    // to judge; the provider launch reports it properly.
    return (await isDirectory(cwd)) ? { kind: "unavailable" } : { kind: "none" };
  }

  // Exit status first: a blocked `.envrc` still prints DIRENV_* JSON on stdout.
  if (outcome.code !== 0) {
    const blocked = BLOCKED.exec(stripAnsi(stderr));
    if (blocked) return { kind: "blocked", envrc: blocked[1] };
    const exit = outcome.signal ? `killed by ${outcome.signal}` : `exit ${outcome.code}`;
    return { kind: "failed", exit, stderrTail: tail(stderr) };
  }
  if (stdout.trim() === "") return { kind: "none" };
  return { kind: "loaded", env: parseEnv(stdout) };
}

// Settles on direnv's exit and the end of its stdout, never on `close`: `close` waits
// for stderr too, which a backgrounded grandchild can hold open forever, and once
// direnv has exited an abort's kill is a no-op that emits nothing.
function run(child: ChildProcess, abort: AbortSignal): Promise<Outcome> {
  return new Promise((resolve) => {
    let exited: Extract<Outcome, { kind: "exited" }> | undefined;
    let stdoutEnded = false;

    const settle = (outcome: Outcome) => {
      abort.removeEventListener("abort", onAbort);
      resolve(outcome);
    };
    const onAbort = () => {
      killGroup(child);
      settle({ kind: "aborted" });
    };
    const finish = async () => {
      if (!exited || !stdoutEnded) return;
      await ended(child.stderr!, STDERR_DRAIN_MS);
      settle(exited);
    };

    abort.addEventListener("abort", onAbort, { once: true });
    child.once("error", (error) => settle({ kind: "error", error }));
    child.once("exit", (code, signal) => {
      exited = { kind: "exited", code, signal };
      void finish();
    });
    child.stdout!.once("end", () => {
      stdoutEnded = true;
      void finish();
    });
  });
}

function ended(stream: Readable, graceMs: number): Promise<void> {
  if (stream.readableEnded) return Promise.resolve();
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, graceMs);
    stream.once("end", () => {
      clearTimeout(timer);
      resolve();
    });
  });
}

function killGroup(child: ChildProcess) {
  if (child.pid === undefined) return;
  try {
    process.kill(-child.pid, "SIGTERM");
  } catch {
    // The group is already gone.
  }
}

// Errors quote their input, and stdout holds variable values, which must never reach
// a message or the log.
function parseEnv(stdout: string): DirenvEnv {
  let parsed: unknown;
  try {
    parsed = JSON.parse(stdout);
  } catch {
    throw new Error("direnv export json printed invalid JSON");
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("direnv export json did not print an object");
  }
  const env: DirenvEnv = {};
  for (const [name, value] of Object.entries(parsed)) {
    if (value !== null && typeof value !== "string") {
      throw new Error(`direnv export json gave ${name} a non-string value`);
    }
    env[name] = value;
  }
  return env;
}

async function isDirectory(dir: string): Promise<boolean> {
  try {
    return (await stat(dir)).isDirectory();
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code === "ENOENT" || code === "ENOTDIR") return false;
    throw error;
  }
}
