import type { BoardBean } from "./rpc.ts";

export const COLUMNS = ["draft", "todo", "in-progress", "completed"] as const;
export const SCRAPPED = "scrapped";

const CONTAINER_TYPES = new Set(["epic", "milestone"]);
const TERMINAL = new Set(["completed", SCRAPPED]);
const PRIORITY_RANK: Record<string, number> = {
  critical: 0,
  high: 1,
  normal: 2,
  low: 3,
  deferred: 4,
};

// Epic lanes group by the epic's own status, most active first.
export const LANE_GROUPS = ["in-progress", "todo", "draft", "completed", SCRAPPED] as const;
export const NO_EPIC_GROUP = "no-epic";

export interface Lane {
  /** The lane's epic, or null for "No epic". */
  epic: BoardBean | null;
  /** The epic's effective status, or NO_EPIC_GROUP; lanes come out grouped by it. */
  group: string;
  /** Cards per visible column, in column order. */
  cells: { column: string; cards: BoardBean[] }[];
  /** Collapsed unless the tab state says otherwise. */
  collapsedByDefault: boolean;
}

// The CLI's ready logic treats an inherited terminal status as the bean's own.
export function columnOf(bean: BoardBean): string {
  return bean.implicitStatus ?? bean.status;
}

function rank(priority: string): number {
  return PRIORITY_RANK[priority] ?? PRIORITY_RANK.normal;
}

function byPriorityThenUpdated(a: BoardBean, b: BoardBean): number {
  return rank(a.priority) - rank(b.priority) || b.updatedAt.localeCompare(a.updatedAt);
}

function byPriorityThenTitle(a: BoardBean, b: BoardBean): number {
  return rank(a.priority) - rank(b.priority) || a.title.localeCompare(b.title);
}

// A parent cycle cannot come out of the CLI, but a seen-set keeps a bad file from
// hanging the client.
function nearestEpic(bean: BoardBean, byId: Map<string, BoardBean>): BoardBean | null {
  const seen = new Set<string>();
  let current = bean.parentId ? byId.get(bean.parentId) : undefined;
  while (current && !seen.has(current.id)) {
    if (current.type === "epic") return current;
    seen.add(current.id);
    current = current.parentId ? byId.get(current.parentId) : undefined;
  }
  return null;
}

function groupRank(group: string): number {
  const index = (LANE_GROUPS as readonly string[]).indexOf(group);
  return index === -1 ? LANE_GROUPS.length : index;
}

/**
 * One lane per epic that has a visible card, grouped by the epic's status in
 * LANE_GROUPS order, then by epic priority and title, with "No epic" last. Epics and milestones are never cards; only epics are lanes.
 *
 * Archiving hides cards, not lanes: an archived epic still heads the lane of any
 * unarchived descendants, which would otherwise scatter into "No epic".
 *
 * `matches`, when given, narrows the cards to those ids, plus every card in the lane of
 * a matching epic. Lanes still come from every bean, so a matching card stays under
 * its epic whether or not the epic matched.
 */
export function layout(
  beans: readonly BoardBean[],
  showScrapped: boolean,
  showArchived: boolean,
  matches: ReadonlySet<string> | null = null,
): Lane[] {
  const columns: string[] = showScrapped ? [...COLUMNS, SCRAPPED] : [...COLUMNS];
  const visible = new Set(columns);
  const byId = new Map(beans.map((bean) => [bean.id, bean]));

  const groups = new Map<string | null, BoardBean[]>();
  for (const bean of beans) {
    if (CONTAINER_TYPES.has(bean.type) || !visible.has(columnOf(bean))) continue;
    if (bean.archived && !showArchived) continue;
    const key = nearestEpic(bean, byId)?.id ?? null;
    if (matches && !matches.has(bean.id) && !(key !== null && matches.has(key))) continue;
    const group = groups.get(key);
    if (group) group.push(bean);
    else groups.set(key, [bean]);
  }

  const lanes: Lane[] = [];
  for (const [key, cards] of groups) {
    const epic = key === null ? null : (byId.get(key) ?? null);
    lanes.push({
      epic,
      group: epic === null ? NO_EPIC_GROUP : columnOf(epic),
      cells: columns.map((column) => ({
        column,
        cards: cards.filter((card) => columnOf(card) === column).sort(byPriorityThenUpdated),
      })),
      collapsedByDefault: epic !== null && TERMINAL.has(columnOf(epic)),
    });
  }
  return lanes.sort((a, b) => {
    if (a.epic === null) return b.epic === null ? 0 : 1;
    if (b.epic === null) return -1;
    return groupRank(a.group) - groupRank(b.group) || byPriorityThenTitle(a.epic, b.epic);
  });
}

export function laneKey(lane: Lane): string {
  return lane.epic?.id ?? "no-epic";
}
