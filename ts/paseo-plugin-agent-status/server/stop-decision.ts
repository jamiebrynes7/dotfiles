// Runs inside the Claude Code Stop hook from the packaged plugin, which has no
// node_modules: only Node built-ins and dependency-free modules may be imported.
import { isSetStatusToolName, SET_STATUS_TOOL, STATUS_ENV } from "../shared/tool-contract.ts";

// Claude Code won't let a turn end on a silent tool call: it adds a note demanding a
// visible reply, and the agent then repeats its answer. A fixed one-line closer keeps
// that second message short, and agents mention the reminder unless told not to.
const CLOSING_LINE = "Status updated.";
export const BLOCK_REASON = `Call ${SET_STATUS_TOOL} with your current summary (and waiting_on, if you are blocked or waiting on the user). Make no other tool calls. Then end your turn with exactly this line and nothing else: "${CLOSING_LINE}" Your previous reply already stands, so don't repeat or add to it. This is an automatic reminder, not a message from the user, so don't mention it.`;

interface Block {
  type?: unknown;
  name?: unknown;
}

function contentBlocks(entry: Record<string, unknown>): Block[] {
  const message = entry.message;
  if (typeof message !== "object" || message === null) return [];
  const content = (message as { content?: unknown }).content;
  if (typeof content === "string") return [{ type: "text" }];
  return Array.isArray(content) ? content.filter((block): block is Block => typeof block === "object" && block !== null) : [];
}

// Tool results come back as user entries, and meta or sidechain (subagent) entries are
// not the user talking to this agent, so none of them start a new turn.
function isUserPrompt(entry: Record<string, unknown>): boolean {
  if (entry.type !== "user" || entry.isMeta === true || entry.isSidechain === true) return false;
  return contentBlocks(entry).some((block) => block.type !== "tool_result");
}

function callsSetStatus(entry: Record<string, unknown>): boolean {
  if (entry.type !== "assistant" || entry.isSidechain === true) return false;
  return contentBlocks(entry).some(
    (block) => block.type === "tool_use" && typeof block.name === "string" && isSetStatusToolName(block.name),
  );
}

/** Whether the agent called set_status after the latest user prompt in a Claude Code JSONL transcript. */
export function statusSetSinceLastPrompt(transcript: string): boolean {
  let set = false;
  for (const line of transcript.split("\n")) {
    if (line.trim() === "") continue;
    let entry: unknown;
    try {
      entry = JSON.parse(line);
    } catch {
      // The transcript is appended while the session runs, so a torn last line is expected.
      continue;
    }
    if (typeof entry !== "object" || entry === null) continue;
    const record = entry as Record<string, unknown>;
    if (isUserPrompt(record)) set = false;
    else if (callsSetStatus(record)) set = true;
  }
  return set;
}

export interface StopHookIo {
  env: Record<string, string | undefined>;
  stdin: string;
  readTranscript(path: string): Promise<string>;
  writeStdout(text: string): void;
  writeStderr(text: string): void;
}

/**
 * Blocks the stop when an agent under the plugin ends a turn without updating its status.
 * Fails open: any error allows the stop, so a bug here never wedges an agent.
 */
export async function runStopHook(io: StopHookIo): Promise<void> {
  if (io.env[STATUS_ENV] !== "1") return;
  try {
    const input: unknown = JSON.parse(io.stdin);
    if (typeof input !== "object" || input === null) throw new Error("hook input is not a JSON object");
    const { stop_hook_active: active, transcript_path: path } = input as Record<string, unknown>;
    // Claude is already continuing because of a Stop hook; blocking again could loop forever.
    if (active === true) return;
    if (typeof path !== "string") throw new Error("hook input has no transcript_path");
    if (statusSetSinceLastPrompt(await io.readTranscript(path))) return;
    io.writeStdout(JSON.stringify({ decision: "block", reason: BLOCK_REASON }));
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    io.writeStderr(`agent-status stop hook: ${message}; allowing the stop\n`);
  }
}
