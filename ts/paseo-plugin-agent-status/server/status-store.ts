import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import path from "node:path";
import { z } from "zod";
import { statusLinkSchema } from "../shared/status.ts";

const StoredAgent = z.object({
  status: z.object({
    summary: z.string(),
    waitingOn: z.string().optional(),
    links: z.array(statusLinkSchema).optional(),
    setAt: z.number(),
  }),
  rowId: z.string().optional(),
});
const StoredFile = z.object({ version: z.literal(1), agents: z.record(z.string(), StoredAgent) });

export type StoredAgentStatus = z.output<typeof StoredAgent>;

export interface StatusStore {
  get(agentId: string): StoredAgentStatus | undefined;
  set(agentId: string, value: StoredAgentStatus): void;
  /** Drops every agent not in `agentIds`. */
  retain(agentIds: ReadonlySet<string>): void;
  flush(): Promise<void>;
}

// Mirrors the daemon's own resolution (server/paseo-home.ts). The plugin process is
// forked from the daemon, so it inherits PASEO_HOME. The plugin directory itself is
// a read-only store path, hence a sibling state directory.
export function defaultStateFile(): string {
  const raw = process.env.PASEO_HOME ?? "~/.paseo";
  const home = raw === "~" || raw.startsWith("~/") ? path.join(homedir(), raw.slice(1)) : raw;
  return path.join(path.resolve(home), "plugin-state", "agent-status.json");
}

async function load(file: string): Promise<Record<string, StoredAgentStatus>> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "ENOENT") {
      console.warn(`agent-status: could not read ${file}; starting with no saved statuses`, error);
    }
    return {};
  }
  try {
    const parsed = StoredFile.safeParse(JSON.parse(text));
    if (parsed.success) return parsed.data.agents;
  } catch {
    // Not JSON at all; handled the same as a schema mismatch below.
  }
  // Starting empty means the next status update overwrites the file; this line is the only trace.
  console.warn(`agent-status: ignoring malformed ${file}; starting with no saved statuses`);
  return {};
}

/** Never rejects: an unreadable or unwritable file degrades to in-memory state. */
export async function openStatusStore(file: string = defaultStateFile()): Promise<StatusStore> {
  const agents = await load(file);
  let writes = Promise.resolve();

  // Writes are serialised so an older snapshot can never land after a newer one.
  function persist() {
    const contents = JSON.stringify({ version: 1, agents });
    writes = writes
      .then(async () => {
        await mkdir(path.dirname(file), { recursive: true });
        const temp = `${file}.tmp`;
        await writeFile(temp, contents);
        await rename(temp, file);
      })
      .catch((error: unknown) => console.error(`agent-status: could not write ${file}`, error));
  }

  return {
    get: (agentId) => agents[agentId],
    set(agentId, value) {
      agents[agentId] = value;
      persist();
    },
    retain(agentIds) {
      const stale = Object.keys(agents).filter((id) => !agentIds.has(id));
      if (stale.length === 0) return;
      for (const id of stale) delete agents[id];
      persist();
    },
    flush: () => writes,
  };
}
