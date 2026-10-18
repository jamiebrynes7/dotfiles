import path from "node:path";
import type { DirenvEnv } from "./evaluate";

export interface Merged {
  env: Record<string, string>;
  unset: string[];
}

// direnv's variables under the request's: an explicit per-launch override (from the
// create request or an earlier plugin) beats the directory's ambient environment.
// PATH is the exception, merged so an override keeps priority without dropping the
// devshell's tools. An unset (`null`) is dropped rather than sent as "": the request
// env is an overlay on the daemon's, so the daemon's value stands.
export function merge(direnv: DirenvEnv, request: Record<string, string>): Merged {
  const env: Record<string, string> = {};
  const unset: string[] = [];
  for (const [name, value] of Object.entries(direnv)) {
    if (value === null) unset.push(name);
    else env[name] = value;
  }
  Object.assign(env, request);
  if (direnv.PATH != null && request.PATH !== undefined) {
    env.PATH = mergePath(request.PATH, direnv.PATH);
  }
  return { env, unset };
}

function mergePath(first: string, second: string): string {
  const entries = first.split(path.delimiter);
  const seen = new Set(entries);
  for (const entry of second.split(path.delimiter)) {
    if (!seen.has(entry)) {
      seen.add(entry);
      entries.push(entry);
    }
  }
  return entries.join(path.delimiter);
}
