import { readFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

// Repository key -> stable plugin directory, as written by home/programs/paseo.nix.
export type Repositories = Record<string, string>;

export type ConfigRead =
  | { kind: "ok"; repositories: Repositories }
  | { kind: "error"; reason: string; detail?: string };

export function configPath(env: NodeJS.ProcessEnv = process.env, home = os.homedir()): string {
  const configHome = env.XDG_CONFIG_HOME || path.join(home, ".config");
  return path.join(configHome, "paseo-repo-skills", "config.json");
}

// Read fresh on every call, so a home-manager switch takes effect without a daemon
// restart. A missing file is an error rather than "nothing declared": the plugin is
// only installed alongside it.
export async function readConfig(file: string): Promise<ConfigRead> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") {
      return { kind: "error", reason: "config file missing", detail: file };
    }
    return { kind: "error", reason: `config file unreadable: ${message(error)}`, detail: file };
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    return { kind: "error", reason: `config file is not valid JSON: ${message(error)}`, detail: file };
  }

  if (!isRecord(parsed) || parsed.version !== 1) {
    return { kind: "error", reason: "config file is not version 1", detail: file };
  }
  const { repositories } = parsed;
  if (!isRecord(repositories) || !Object.values(repositories).every((v) => typeof v === "string")) {
    return {
      kind: "error",
      reason: 'config file "repositories" is not an object of strings',
      detail: file,
    };
  }
  return { kind: "ok", repositories: repositories as Repositories };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
