import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { z } from "zod";

const StoredTimes = z.record(z.string(), z.number());

export interface ResponseStore {
  all(): Record<string, number>;
  record(agentId: string, at: number): void;
  /** Drops every agent not in `agentIds`. */
  retain(agentIds: ReadonlySet<string>): void;
  flush(): Promise<void>;
}

// Mirrors the daemon's own resolution (server/paseo-home.ts). The plugin process is
// forked from the daemon, so it inherits PASEO_HOME. The plugin directory itself is
// a read-only store path, hence a sibling state directory.
function stateFile(): string {
  const raw = process.env.PASEO_HOME ?? "~/.paseo";
  const home = raw === "~" || raw.startsWith("~/") ? path.join(homedir(), raw.slice(1)) : raw;
  return path.join(path.resolve(home), "plugin-state", "last-response.json");
}

async function load(file: string): Promise<Record<string, number>> {
  try {
    const parsed = StoredTimes.safeParse(JSON.parse(await readFile(file, "utf8")));
    if (parsed.success) return parsed.data;
    // Starting empty means the next turn end overwrites it; this line is the only trace.
    console.error(`last-response: ignoring malformed ${file}`);
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      console.error(`last-response: could not read ${file}`, error);
    }
  }
  return {};
}

/** Never rejects: an unreadable or unwritable file degrades to in-memory state. */
export async function openStore(): Promise<ResponseStore> {
  const file = stateFile();
  const times = await load(file);
  let writes = Promise.resolve();

  // Writes are serialised so an older snapshot can never land after a newer one.
  function persist() {
    const contents = JSON.stringify(times);
    writes = writes
      .then(async () => {
        await mkdir(path.dirname(file), { recursive: true });
        const temp = `${file}.tmp`;
        await writeFile(temp, contents);
        await rename(temp, file);
      })
      .catch((error: unknown) => console.error(`last-response: could not write ${file}`, error));
  }

  return {
    all: () => ({ ...times }),
    record(agentId, at) {
      times[agentId] = at;
      persist();
    },
    retain(agentIds) {
      const stale = Object.keys(times).filter((id) => !agentIds.has(id));
      if (stale.length === 0) return;
      for (const id of stale) delete times[id];
      persist();
    },
    flush: () => writes,
  };
}
