// Claude Code's `authentication_failed` replies, as of 2.1.308. Under paseo's
// sdk-cli launch it sends the "Failed to authenticate" forms; the "· Please run
// /login" forms are its interactive ones, kept in case that changes.
const AUTH_FAILURE_MESSAGES = [
  "Failed to authenticate: OAuth session expired and could not be refreshed",
  "Failed to authenticate: OAuth token revoked. Please log in again or contact your administrator.",
  "Login expired · Please run /login",
  "OAuth token revoked · Please run /login",
  "Not logged in · Please run /login",
];

// Matched anywhere in a finished reply, not only at the start: a real `turn_failed`
// reaches the timeline with paseo's SYSTEM_ERROR_PREFIX in front. A wording missing
// here degrades to a plain message, so supporting one is a single new entry.
const AUTH_FAILURE_PHRASES = [
  "OAuth session expired",
  "OAuth token revoked",
  "OAuth access token has been revoked",
  "Login expired · Please run /login",
  "Not logged in · Please run /login",
];

const SYSTEM_ERROR_PREFIX = "[System Error] ";

// The real messages are one short line. The cap keeps a reply that merely quotes a
// phrase, such as an agent discussing this file, from turning into a card for good.
const MAX_MESSAGE_CHARS = 500;

/**
 * A streaming reply must be exactly one of the known messages. A reload re-streams
 * the provider's history with no turn completion after it, so the auth reply sits in
 * the live head, projected as streaming, until the next message; an exact match
 * catches it there without flashing a card for a live reply that quotes a phrase.
 */
export function matchAuthFailure(text: string, phase: "streaming" | "complete"): boolean {
  if (phase === "streaming") {
    const trimmed = text.trim();
    const bare = trimmed.startsWith(SYSTEM_ERROR_PREFIX)
      ? trimmed.slice(SYSTEM_ERROR_PREFIX.length)
      : trimmed;
    return AUTH_FAILURE_MESSAGES.includes(bare);
  }
  if (text.length > MAX_MESSAGE_CHARS) return false;
  return AUTH_FAILURE_PHRASES.some((phrase) => text.includes(phrase));
}
