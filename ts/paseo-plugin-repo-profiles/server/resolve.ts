import type { ConfigRead } from "./config.ts";
import type { RemoteList } from "./git.ts";
import { normaliseRemoteUrl } from "./remote-url.ts";

// The subset of AgentSessionConfig this plugin reads.
export interface SessionConfig {
  provider: string;
  cwd: string;
  providerOptions?: Record<string, unknown>;
}

export type Decision =
  // Not ours to touch: a non-Claude agent, no repository, no matching remote.
  | { kind: "unchanged" }
  // A declared repository may be involved, but its skills cannot be loaded.
  | { kind: "skipped"; reason: string; detail?: string }
  | { kind: "load"; key: string; pluginDir: string; alsoMatched: string[] };

export interface Deps {
  readConfig(): Promise<ConfigRead>;
  listRemoteUrls(cwd: string): Promise<RemoteList>;
  isDirectory(path: string): Promise<boolean>;
}

export async function decide(config: SessionConfig, deps: Deps): Promise<Decision> {
  // Exact: a custom provider that `extends: "claude"` runs the Claude CLI too, but the
  // hook payload carries no way to resolve what a provider extends.
  if (config.provider !== "claude") return { kind: "unchanged" };

  // Remotes before the config, so an agent outside any repository stays silent even
  // when the config is broken.
  const remotes = await deps.listRemoteUrls(config.cwd);
  if (remotes.kind === "not-a-repository") return { kind: "unchanged" };
  if (remotes.kind === "error") return { ...remotes, kind: "skipped" };

  const read = await deps.readConfig();
  if (read.kind === "error") return { ...read, kind: "skipped" };

  const matched = matchKeys(remotes.urls, Object.keys(read.repositories));
  const [key, ...alsoMatched] = matched;
  if (key === undefined) return { kind: "unchanged" };

  const { pluginDir } = read.repositories[key]!;
  if (pluginDir === undefined) return { kind: "unchanged" };
  if (!(await deps.isDirectory(pluginDir))) {
    return {
      kind: "skipped",
      reason: `plugin folder missing or unreadable for ${key}`,
      detail: pluginDir,
    };
  }

  const extraArgs = config.providerOptions?.extraArgs;
  if (extraArgs !== undefined && !isRecord(extraArgs)) {
    return { kind: "skipped", reason: "providerOptions.extraArgs is not an object" };
  }
  // Our own value coming back: Paseo re-creates a stored agent that never got a
  // provider session from its saved config, which already carries it.
  if (extraArgs !== undefined && extraArgs["plugin-dir"] === pluginDir) {
    return { kind: "unchanged" };
  }
  if (extraArgs !== undefined && Object.hasOwn(extraArgs, "plugin-dir")) {
    return {
      kind: "skipped",
      reason: "plugin-dir already set",
      detail: String(extraArgs["plugin-dir"]),
    };
  }

  return { kind: "load", key, pluginDir, alsoMatched };
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

// The cast is safe after decide(), which skips when extraArgs is not a record.
export function withPluginDir<T extends SessionConfig>(config: T, pluginDir: string): T {
  const providerOptions = config.providerOptions ?? {};
  const extraArgs = (providerOptions.extraArgs as Record<string, string | null> | undefined) ?? {};
  return {
    ...config,
    providerOptions: {
      ...providerOptions,
      extraArgs: { ...extraArgs, "plugin-dir": pluginDir },
    },
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
