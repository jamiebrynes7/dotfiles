import { execFile } from "node:child_process";
import { readFile, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import { promisify } from "node:util";

const exec = promisify(execFile);
// Four commands at most run in sequence; index.server.ts's wait covers all four.
export const COMMAND_TIMEOUT_MS = 2_000;
export const MAX_COMMANDS = 4;
// `git worktree add` writes the worktree's `.git` file moments before paseo emits
// `workspace.created`. An older one means the event is for an existing directory.
const FRESH_MS = 120_000;

export type AllowDecision =
  { kind: "allowed"; worktree: string; source: string } | { kind: "skipped"; reason: string };

// Allowing a project's root checkout is the per-project opt-in: a new paseo
// worktree of it is allowed in turn. This trusts the project, not the worktree's
// content, so a `checkout-pr` of a fork PR against an allowed project is allowed
// too (docs/specs/2026-10-19-paseo-direnv-worktree-allow.md, "Accepted risk").
//
// paseo emits `workspace.created` for any new workspace, including a local one
// opened on an existing worktree or minted by an agent's `create_agent` tool, so
// the freshness and committed-`.envrc` checks are what keep this to new worktrees
// and keep an edited `.envrc` refused rather than silently re-approved.
export async function allowNewWorktree(cwd: string): Promise<AllowDecision> {
  const root = await worktreesRoot();
  if (!isInside(cwd, root)) return skip(`not under paseo's worktrees root ${root}`);

  const [worktree, commonDir] = (
    await git(cwd, ["rev-parse", "--show-toplevel", "--path-format=absolute", "--git-common-dir"])
  ).split("\n");
  // As paseo derives a worktree's project: the common dir's parent, unless bare.
  const source = path.basename(commonDir) === ".git" ? path.dirname(commonDir) : commonDir;
  if (source === worktree) return skip("not a linked worktree");

  const age = Date.now() - (await stat(path.join(worktree, ".git"))).mtimeMs;
  if (age > FRESH_MS) return skip("not a new worktree (its .git is older than the event)");

  if (!(await exists(path.join(worktree, ".envrc")))) return skip("worktree has no .envrc");
  // Empty only for a tracked file matching HEAD: untracked is `??`, ignored `!!`.
  const envrcStatus = await git(worktree, ["status", "--porcelain", "--ignored", "--", ".envrc"]);
  if (envrcStatus !== "") return skip("worktree's .envrc is not committed as-is");

  // A parent directory's `.envrc` in scope is not the project's own.
  const sourceEnvrc = path.join(source, ".envrc");
  const status = await direnvStatus(source);
  if (status?.path !== sourceEnvrc) {
    return skip(`source checkout ${source} has no .envrc of its own`);
  }
  // direnv keys an allow on the path it was given, so one made through a symlinked
  // path does not count for the real path checked here.
  if (status.allowed !== 0) {
    return skip(`source checkout's ${sourceEnvrc} is not allowed (at its real path)`);
  }

  await exec("direnv", ["allow", worktree], { env: process.env, timeout: COMMAND_TIMEOUT_MS });
  return { kind: "allowed", worktree, source };
}

function skip(reason: string): AllowDecision {
  return { kind: "skipped", reason };
}

// paseo's own resolution: `worktrees.root` from config.json (trimmed), relative to
// PASEO_HOME, else `$PASEO_HOME/worktrees`. The daemon's PASEO_HOME reaches this
// process because plugins are forked with the daemon's environment.
async function worktreesRoot(): Promise<string> {
  const home = path.resolve(expandTilde(process.env.PASEO_HOME ?? "~/.paseo"));
  let configured: unknown;
  try {
    const config = JSON.parse(await readFile(path.join(home, "config.json"), "utf8"));
    configured = config?.worktrees?.root;
  } catch {
    // No or unreadable config: paseo falls back to the default too.
  }
  if (typeof configured === "string" && configured.trim() !== "") {
    return path.resolve(home, expandTilde(configured.trim()));
  }
  return path.join(home, "worktrees");
}

function expandTilde(value: string): string {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

export function isInside(child: string, parent: string): boolean {
  const relative = path.relative(parent, child);
  return relative !== "" && !relative.startsWith("..") && !path.isAbsolute(relative);
}

async function git(cwd: string, args: string[]): Promise<string> {
  const { stdout } = await exec("git", args, { cwd, timeout: COMMAND_TIMEOUT_MS });
  return stdout.trim();
}

// `allowed` is direnv's status enum: 0 allowed, 1 not allowed, 2 denied.
async function direnvStatus(cwd: string): Promise<{ path: string; allowed: number } | null> {
  const { stdout } = await exec("direnv", ["status", "--json"], {
    cwd,
    env: process.env,
    timeout: COMMAND_TIMEOUT_MS,
  });
  const found = JSON.parse(stdout)?.state?.foundRC;
  if (!found || typeof found.path !== "string" || typeof found.allowed !== "number") return null;
  return { path: found.path, allowed: found.allowed };
}

async function exists(file: string): Promise<boolean> {
  try {
    await stat(file);
    return true;
  } catch {
    return false;
  }
}
