import { createHash } from "node:crypto";
import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";

export const CONFIG_FILE = ".beans.yml";
const DEFAULT_DATA_PATH = ".beans";

export interface Project {
  config: string;
  dataDir: string;
}

// The same upward search the CLI does, so the fingerprint watches the project the
// board query will read. Only a missing file moves the search up; anything else
// (permissions, a directory named `.beans.yml`) is an error, not "no project".
export async function findProject(directory: string): Promise<Project | null> {
  let dir = path.resolve(directory);
  for (;;) {
    const config = path.join(dir, CONFIG_FILE);
    const text = await readFile(config, "utf8").catch(missing);
    if (text !== null) return { config, dataDir: path.resolve(dir, dataPath(text)) };
    const parent = path.dirname(dir);
    if (parent === dir) return null;
    dir = parent;
  }
}

// Just enough YAML for `beans.path`, which is all the fingerprint needs. A config
// the CLI rejects still fails the board query, which reports the CLI's own error.
export function dataPath(yaml: string): string {
  let inBeans = false;
  for (const line of yaml.split(/\r?\n/)) {
    if (/^\S/.test(line)) {
      inBeans = /^beans\s*:\s*(#.*)?$/.test(line);
      continue;
    }
    const match = inBeans ? /^\s+path\s*:\s*(.*?)\s*(#.*)?$/.exec(line) : null;
    if (!match) continue;
    const value = match[1].replace(/^(["'])(.*)\1$/, "$2");
    if (value !== "") return value;
  }
  return DEFAULT_DATA_PATH;
}

function missing(error: NodeJS.ErrnoException): null {
  if (error.code === "ENOENT") return null;
  throw error;
}

async function listFiles(dir: string, prefix = ""): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true });
  const files: string[] = [];
  for (const entry of entries) {
    const relative = path.join(prefix, entry.name);
    if (entry.isDirectory()) files.push(...(await listFiles(path.join(dir, entry.name), relative)));
    else files.push(relative);
  }
  return files;
}

/**
 * A hash of the config's mtime and every data file's path, size, inode and times,
 * archive included, so adding, editing, removing or archiving a bean changes it.
 * Stats only. The inode and ctime catch an atomic rename-write whose size and
 * coarse mtime match the old file's.
 */
export async function fingerprintOf(project: Project): Promise<string> {
  const hash = createHash("sha256");
  hash.update(`${(await stat(project.config)).mtimeMs}\0`);
  // Git tracks no empty directories, so a fresh checkout of a project with no beans
  // has a config and no data directory: an empty board, not an error.
  const files = (await listFiles(project.dataDir).catch(missing)) ?? [];
  for (const file of files.sort()) {
    // Archived or renamed between the listing and the stat: the next poll sees it.
    const info = await stat(path.join(project.dataDir, file)).catch(missing);
    if (!info) continue;
    hash.update(`${file}\0${info.size}\0${info.ino}\0${info.mtimeMs}\0${info.ctimeMs}\0`);
  }
  return hash.digest("hex");
}
