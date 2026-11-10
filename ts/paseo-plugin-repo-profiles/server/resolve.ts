import type { ConfigRead, Profile } from "./config.ts";
import type { RemoteList } from "./git.ts";
import { normaliseRemoteUrl } from "./remote-url.ts";

// The subset of AgentSessionConfig this plugin reads.
export interface SessionConfig {
  provider: string;
  cwd: string;
  providerOptions?: Record<string, unknown>;
}

// What a profile field is called to the user.
export type FieldLabel = "skills" | "settings";

export interface Problem {
  // Absent when the problem stops the whole profile, not one field.
  field?: FieldLabel;
  reason: string;
  // The path or value the reason is about.
  detail?: string;
}

// `extraArgs` keys to set, and why anything that should have loaded didn't. Both
// empty means the request is not ours to touch: a non-Claude agent, no repository, no
// matching remote, or a profile already applied.
export interface Decision {
  key?: string;
  set: Record<string, string>;
  // Fields whose value the agent launches with, whether set now or already ours.
  loaded: FieldLabel[];
  problems: Problem[];
}

export interface Deps {
  readConfig(): Promise<ConfigRead>;
  listRemoteUrls(cwd: string): Promise<RemoteList>;
  isDirectory(path: string): Promise<boolean>;
  isReadableFile(path: string): Promise<boolean>;
}

interface Field {
  label: FieldLabel;
  arg: string;
  path(profile: Profile): string | undefined;
  exists(deps: Deps, path: string): Promise<boolean>;
  missing: string;
}

// Each field maps to one CLI flag, and is applied independently of the others.
const FIELDS: readonly Field[] = [
  {
    label: "skills",
    arg: "plugin-dir",
    path: (profile) => profile.pluginDir,
    exists: (deps, path) => deps.isDirectory(path),
    missing: "plugin folder missing or unreadable",
  },
  {
    label: "settings",
    arg: "settings",
    path: (profile) => profile.settings,
    // Readable is enough: Nix rendered it as JSON, and a bad file fails at launch.
    exists: (deps, path) => deps.isReadableFile(path),
    missing: "settings file missing or unreadable",
  },
];

const UNCHANGED: Decision = { set: {}, loaded: [], problems: [] };

export async function decide(config: SessionConfig, deps: Deps): Promise<Decision> {
  // Exact: a custom provider that `extends: "claude"` runs the Claude CLI too, but the
  // hook payload carries no way to resolve what a provider extends.
  if (config.provider !== "claude") return UNCHANGED;

  // Remotes before the config, so an agent outside any repository stays silent even
  // when the config is broken.
  const remotes = await deps.listRemoteUrls(config.cwd);
  if (remotes.kind === "not-a-repository") return UNCHANGED;
  if (remotes.kind === "error") return failed(remotes);

  const read = await deps.readConfig();
  if (read.kind === "error") return failed(read);

  const matched = matchKeys(remotes.urls, Object.keys(read.repositories));
  const [key, ...alsoMatched] = matched;
  if (key === undefined) return UNCHANGED;

  const extraArgs = config.providerOptions?.extraArgs;
  if (extraArgs !== undefined && !isRecord(extraArgs)) {
    return { key, ...failed({ reason: "providerOptions.extraArgs is not an object" }) };
  }

  const profile = read.repositories[key]!;
  const decision: Decision = { key, set: {}, loaded: [], problems: [] };
  if (alsoMatched.length > 0) {
    decision.problems.push({
      reason: "remotes also match other declared repositories; only the first one's profile is loaded",
      detail: alsoMatched.join(", "),
    });
  }

  for (const field of FIELDS) {
    const path = field.path(profile);
    if (path === undefined) continue;
    // First, even for our own value coming back: a launch with a missing settings file
    // fails, and this warning is the only explanation the user gets.
    if (!(await field.exists(deps, path))) {
      decision.problems.push({ field: field.label, reason: `${field.missing} for ${key}`, detail: path });
      continue;
    }
    const current = extraArgs?.[field.arg];
    // Our own value coming back: Paseo re-creates a stored agent that never got a
    // provider session from its saved config, which already carries it.
    if (current === path) {
      decision.loaded.push(field.label);
      continue;
    }
    if (extraArgs !== undefined && Object.hasOwn(extraArgs, field.arg)) {
      decision.problems.push({
        field: field.label,
        reason: `${field.arg} already set`,
        detail: String(current),
      });
      continue;
    }
    decision.set[field.arg] = path;
    decision.loaded.push(field.label);
  }

  // Nothing new to set and no field went wrong: a re-created agent already carrying
  // its whole profile, whose multi-match was reported when it was first created. A
  // field problem posts the whole row again, replacing the first one (same row id).
  const fieldProblems = decision.problems.filter((problem) => problem.field !== undefined);
  if (Object.keys(decision.set).length === 0 && fieldProblems.length === 0) return UNCHANGED;
  return decision;
}

function failed(problem: { reason: string; detail?: string }): Decision {
  const { reason, detail } = problem;
  return { set: {}, loaded: [], problems: [detail === undefined ? { reason } : { reason, detail }] };
}

// Declared keys matched by any remote, in remote order, without repeats. Folded for
// case because GitHub ignores it; the Nix side rejects keys that differ only in case.
export function matchKeys(urls: readonly string[], keys: readonly string[]): string[] {
  const byFolded = new Map(keys.map((key) => [key.toLowerCase(), key]));
  const matched: string[] = [];
  for (const url of urls) {
    const normalised = normaliseRemoteUrl(url);
    const key = normalised === null ? undefined : byFolded.get(normalised.toLowerCase());
    if (key !== undefined && !matched.includes(key)) matched.push(key);
  }
  return matched;
}

// The cast is safe after decide(), which reports a problem when extraArgs is not a
// record and sets nothing.
export function withExtraArgs<T extends SessionConfig>(config: T, set: Record<string, string>): T {
  const providerOptions = config.providerOptions ?? {};
  const extraArgs = (providerOptions.extraArgs as Record<string, string | null> | undefined) ?? {};
  return {
    ...config,
    providerOptions: { ...providerOptions, extraArgs: { ...extraArgs, ...set } },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
