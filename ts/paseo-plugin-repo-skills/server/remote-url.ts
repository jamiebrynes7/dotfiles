// git's scp-like syntax, `[user@]host:path`: only when the colon comes before any
// slash, which is also how git tells it apart from a local path.
const SCP_LIKE = /^(?:[^@/]+@)?([^/:]+):(.+)$/;
const HAS_SCHEME = /^[a-z][a-z0-9+.-]*:\/\//i;

// Normalises a remote URL to the `host/owner/repo` form the Nix side validates keys
// against: lowercase host, no scheme, user or port, no trailing `/` or `.git`. Path
// case is kept; matching folds it. A path with more than two segments (a GitLab
// subgroup) is returned whole and so never matches a declared key. Local and
// `file://` remotes have no host and give null.
export function normaliseRemoteUrl(url: string): string | null {
  let host: string;
  let path: string;
  if (HAS_SCHEME.test(url)) {
    let parsed: URL;
    try {
      parsed = new URL(url);
    } catch {
      return null;
    }
    if (parsed.protocol === "file:") return null;
    host = parsed.hostname;
    path = parsed.pathname;
  } else {
    const match = SCP_LIKE.exec(url);
    if (match === null) return null;
    host = match[1]!;
    path = match[2]!;
  }
  path = path
    .replace(/^\/+/, "")
    .replace(/\/+$/, "")
    .replace(/\.git$/, "");
  if (host === "" || path === "") return null;
  return `${host.toLowerCase()}/${path}`;
}
