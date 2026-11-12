// Claude Code Stop hook entry point, run as `node server/stop-hook.ts` from the packaged
// plugin. Not imported by the plugin's daemon half.
import { readFile } from "node:fs/promises";
import { text } from "node:stream/consumers";
import { runStopHook } from "./stop-decision.ts";

await runStopHook({
  env: process.env,
  stdin: await text(process.stdin),
  readTranscript: (path) => readFile(path, "utf8"),
  writeStdout: (output) => process.stdout.write(output),
  writeStderr: (output) => process.stderr.write(output),
});
