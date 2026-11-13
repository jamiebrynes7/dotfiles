import type { StatusLink } from "./status.ts";

// Regexes rather than URL: React Native's URL leaves hostname and pathname unimplemented.
const GITHUB_PR = /^https?:\/\/github\.com\/([^/?#]+)\/([^/?#]+)\/pull\/(\d+)\/?(?:[?#].*)?$/;
const SCHEME_AND_TRAILER = /^https?:\/\/|\/?(?:[?#].*)?$/g;

/**
 * "owner/repo#1234" for a GitHub pull request, "Review" for a review (whose URLs are
 * long and say nothing), and otherwise the URL without its scheme, query or fragment.
 * A kind this client doesn't know reads as "other".
 */
export function linkLabel({ kind, url }: StatusLink): string {
  if (kind === "review") return "Review";
  const pr = kind === "pr" ? GITHUB_PR.exec(url) : null;
  if (pr) return `${pr[1]}/${pr[2]}#${pr[3]}`;
  return url.replace(SCHEME_AND_TRAILER, "");
}
