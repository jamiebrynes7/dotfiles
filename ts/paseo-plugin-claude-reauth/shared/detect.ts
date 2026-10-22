// Matched anywhere in the text, not at the start: a real `turn_failed` reaches the
// timeline with paseo's SYSTEM_ERROR_PREFIX in front. A wording missing here
// degrades to a plain message, so supporting one is a single new entry.
const AUTH_FAILURE_PHRASES = [
  "OAuth session expired",
  "OAuth access token has been revoked",
  "Not logged in · Please run /login",
];

// The real messages are one short line. The cap keeps a reply that merely quotes a
// phrase, such as an agent discussing this file, from turning into a card for good.
const MAX_MESSAGE_CHARS = 500;

export function matchAuthFailure(text: string): boolean {
  if (text.length > MAX_MESSAGE_CHARS) return false;
  return AUTH_FAILURE_PHRASES.some((phrase) => text.includes(phrase));
}
