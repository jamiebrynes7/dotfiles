const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** "just now", "12m ago", "3h ago", "2d ago". A negative age (client clock behind the daemon's) reads as "just now". */
export function formatAge(ageMs: number): string {
  if (ageMs < MINUTE) return "just now";
  if (ageMs < HOUR) return `${Math.floor(ageMs / MINUTE)}m ago`;
  if (ageMs < DAY) return `${Math.floor(ageMs / HOUR)}h ago`;
  return `${Math.floor(ageMs / DAY)}d ago`;
}

export function formatStatusLine(
  status: { summary: string; waitingOn?: string; setAt: number },
  now: number,
): string {
  const waiting = status.waitingOn ? ` — waiting on ${status.waitingOn}` : "";
  return `${status.summary}${waiting} · ${formatAge(now - status.setAt)}`;
}
