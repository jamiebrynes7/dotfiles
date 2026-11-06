import { spawn } from "node:child_process";

// Per call, and there are two: well inside Paseo's 30-second hook limit, which fails
// agent creation outright when exceeded.
export const GIT_TIMEOUT_MS = 5_000;

export type RemoteList =
  | { kind: "not-a-repository" }
  | { kind: "ok"; urls: string[] }
  | { kind: "error"; reason: string };

export interface GitOptions {
  signal?: AbortSignal;
  timeoutMs?: number;
  git?: string;
}

// LC_ALL=C below keeps this message stable.
const NO_REPOSITORY = /^fatal: not a git repository \(or any/m;

// A GIT_DIR, GIT_WORK_TREE or GIT_CONFIG_* in the daemon's environment would point
// both calls somewhere other than the agent's cwd.
function gitEnv(): NodeJS.ProcessEnv {
  const env = Object.fromEntries(
    Object.entries(process.env).filter(([name]) => !name.startsWith("GIT_")),
  );
  return { ...env, LC_ALL: "C" };
}

type RunResult =
  | { kind: "exited"; code: number | null; stdout: string; stderr: string }
  | { kind: "failed"; reason: string };

// Remote URLs of the repository at `cwd`, in config order (`git remote -v` sorts by
// name, which would make "first match" mean alphabetical). `--local` reads the
// repository's own config, which a worktree shares with its main checkout.
export async function listRemoteUrls(cwd: string, options: GitOptions = {}): Promise<RemoteList> {
  const inside = await run(["-C", cwd, "rev-parse", "--git-dir"], options);
  if (inside.kind === "failed") return { kind: "error", reason: inside.reason };
  if (inside.code !== 0) {
    // Only git's search coming up empty is silent. A broken worktree link, dubious
    // ownership or a vanished cwd also exit 128, and those are failures to report.
    if (NO_REPOSITORY.test(inside.stderr)) return { kind: "not-a-repository" };
    return {
      kind: "error",
      reason: `git rev-parse exited ${inside.code} in ${cwd}: ${inside.stderr.trim()}`,
    };
  }

  // --local turns includes off unless asked, and a repository config may include another.
  const listed = await run(
    ["-C", cwd, "config", "--local", "--includes", "--null", "--get-regexp", "^remote\\..*\\.url$"],
    options,
  );
  if (listed.kind === "failed") return { kind: "error", reason: listed.reason };
  // 1 is git config's "no matching key": a repository with no remotes.
  if (listed.code === 1) return { kind: "ok", urls: [] };
  if (listed.code !== 0) {
    return {
      kind: "error",
      reason: `git config exited ${listed.code} in ${cwd}: ${listed.stderr.trim()}`,
    };
  }
  // --null prints `<key>\n<value>\0` per entry.
  const urls = listed.stdout
    .split("\0")
    .filter((entry) => entry !== "")
    .map((entry) => entry.slice(entry.indexOf("\n") + 1));
  return { kind: "ok", urls };
}

// Settles on the timeout itself rather than waiting for the child's pipes to close,
// so a grandchild still holding them cannot keep the hook past its budget.
function run(args: string[], options: GitOptions): Promise<RunResult> {
  const { signal, timeoutMs = GIT_TIMEOUT_MS, git = "git" } = options;
  const command = `git ${args.slice(2).join(" ")}`;
  return new Promise((resolve) => {
    if (signal?.aborted) {
      resolve({ kind: "failed", reason: `${command} aborted` });
      return;
    }
    let stdout = "";
    let stderr = "";
    let settled = false;
    const child = spawn(git, args, { stdio: ["ignore", "pipe", "pipe"], env: gitEnv() });
    const finish = (result: RunResult) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      resolve(result);
    };
    const onAbort = () => finish({ kind: "failed", reason: `${command} aborted` });
    const timer = setTimeout(
      () => finish({ kind: "failed", reason: `${command} timed out after ${timeoutMs}ms` }),
      timeoutMs,
    );
    signal?.addEventListener("abort", onAbort, { once: true });
    child.stdout.setEncoding("utf8").on("data", (chunk: string) => (stdout += chunk));
    child.stderr.setEncoding("utf8").on("data", (chunk: string) => (stderr += chunk));
    child.on("error", (error) => finish({ kind: "failed", reason: `${command}: ${error.message}` }));
    child.on("close", (code) => finish({ kind: "exited", code, stdout, stderr }));
  });
}
