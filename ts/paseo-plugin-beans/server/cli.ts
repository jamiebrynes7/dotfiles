import { spawn } from "node:child_process";

// Inside the daemon's 30 s plugin RPC limit, so a hung CLI is reported as a timeout
// rather than as the RPC's own.
export const CLI_TIMEOUT_MS = 20_000;
const STDERR_TAIL = 2_000;

export interface CliOptions {
  timeoutMs?: number;
  beans?: string;
}

function tail(text: string): string {
  const trimmed = text.trim();
  return trimmed.length > STDERR_TAIL ? `…${trimmed.slice(-STDERR_TAIL)}` : trimmed;
}

/**
 * Runs `beans graphql --json` in `cwd` and returns its `data`. The query is a fixed
 * string; values travel only as `-v` JSON variables. Settles on the timer itself, so
 * a grandchild holding the pipes cannot keep the RPC past its budget.
 */
export function graphql(
  cwd: string,
  query: string,
  variables: Record<string, unknown> = {},
  options: CliOptions = {},
): Promise<unknown> {
  const { timeoutMs = CLI_TIMEOUT_MS, beans = "beans" } = options;
  const args = ["graphql", "--json", "-v", JSON.stringify(variables), query];
  return new Promise((resolve, reject) => {
    let stdout = "";
    let stderr = "";
    let settled = false;
    const child = spawn(beans, args, { cwd, stdio: ["ignore", "pipe", "pipe"] });
    const finish = (error: Error | null, data?: unknown) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
      if (error) reject(error);
      else resolve(data);
    };
    const timer = setTimeout(
      () => finish(new Error(`beans timed out after ${timeoutMs / 1000}s in ${cwd}`)),
      timeoutMs,
    );
    child.stdout.setEncoding("utf8").on("data", (chunk: string) => (stdout += chunk));
    child.stderr.setEncoding("utf8").on("data", (chunk: string) => (stderr += chunk));
    child.on("error", (error: NodeJS.ErrnoException) =>
      finish(
        new Error(
          error.code === "ENOENT"
            ? `\`${beans}\` is not on the daemon's PATH`
            : `could not run beans: ${error.message}`,
        ),
      ),
    );
    child.on("close", (code, signal) => {
      if (code !== 0) {
        const how = code === null ? `was killed by ${signal}` : `exited ${code}`;
        finish(new Error([`beans ${how} in ${cwd}`, tail(stderr)].filter(Boolean).join(": ")));
        return;
      }
      let parsed: unknown;
      try {
        parsed = JSON.parse(stdout);
      } catch {
        finish(new Error(`beans printed output that is not JSON: ${tail(stdout)}`));
        return;
      }
      try {
        finish(null, unwrap(parsed));
      } catch (error) {
        finish(error as Error);
      }
    });
  });
}

// `--json` prints the data object itself, but a GraphQL-shaped `{ data, errors }`
// is unwrapped too, so `errors` in otherwise valid output is never mistaken for data.
function unwrap(parsed: unknown): unknown {
  if (typeof parsed !== "object" || parsed === null) return parsed;
  const record = parsed as Record<string, unknown>;
  if (Array.isArray(record.errors) && record.errors.length > 0) {
    const messages = record.errors.map((error) =>
      typeof error === "object" && error !== null && "message" in error
        ? String(error.message)
        : JSON.stringify(error),
    );
    throw new Error(`beans query failed: ${messages.join("; ")}`);
  }
  return "data" in record && Object.keys(record).every((key) => key === "data" || key === "errors")
    ? record.data
    : parsed;
}
