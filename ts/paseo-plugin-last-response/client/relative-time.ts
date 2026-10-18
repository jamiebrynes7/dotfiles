const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

function unit(count: number, name: string): string | null {
  if (count === 0) return null;
  return `${count} ${name}${count === 1 ? "" : "s"}`;
}

/**
 * "Just now", "1 minute ago", "1 hour 5 minutes ago", "2 days 3 hours ago": the two
 * largest non-zero units. A negative age (client clock behind the daemon's) reads as
 * "Just now".
 */
export function formatAge(ageMs: number): string {
  if (ageMs < MINUTE) return "Just now";
  const days = Math.floor(ageMs / DAY);
  const hours = Math.floor((ageMs % DAY) / HOUR);
  const minutes = Math.floor((ageMs % HOUR) / MINUTE);
  const parts =
    days > 0
      ? [unit(days, "day"), unit(hours, "hour")]
      : [unit(hours, "hour"), unit(minutes, "minute")];
  return `${parts.filter((part) => part !== null).join(" ")} ago`;
}
