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

export interface Cell {
  column: string;
  cards: BoardBean[];
}

export interface Row {
  /** The row's feature, or null for "Other" (or a lane's only row). */
  feature: BoardBean | null;
  /** The feature card is shown only as context: dimmed and left out of counts. */
  featureIsContext: boolean;
  /** Cards per visible column, in column order; a feature row's feature card leads its cell. */
  cells: Cell[];
  /** Completed and scrapped features start collapsed; always false for "Other". */
  collapsedByDefault: boolean;
}

export interface Lane {
  /** The lane's epic, or null for "No epic". */
  epic: BoardBean | null;
  /** The epic's effective status, or NO_EPIC_GROUP; lanes come out grouped by it. */
  group: string;
  /** Feature rows in LANE_GROUPS order, then "Other" if it has any cards. */
  rows: Row[];
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
function* ancestors(bean: BoardBean, byId: Map<string, BoardBean>): Generator<BoardBean> {
  const seen = new Set<string>();
  let current = bean.parentId ? byId.get(bean.parentId) : undefined;
  while (current && !seen.has(current.id)) {
    yield current;
    seen.add(current.id);
    current = current.parentId ? byId.get(current.parentId) : undefined;
  }
}

function nearestEpic(bean: BoardBean, byId: Map<string, BoardBean>): BoardBean | null {
  for (const ancestor of ancestors(bean, byId)) {
    if (ancestor.type === "epic") return ancestor;
  }
  return null;
}

// Stops at an epic: a feature above it belongs to another lane.
function nearestFeature(bean: BoardBean, byId: Map<string, BoardBean>): BoardBean | null {
  for (const ancestor of ancestors(bean, byId)) {
    if (ancestor.type === "feature") return ancestor;
    if (ancestor.type === "epic") return null;
  }
  return null;
}

function groupRank(group: string): number {
  const index = (LANE_GROUPS as readonly string[]).indexOf(group);
  return index === -1 ? LANE_GROUPS.length : index;
}

/**
 * One lane per epic that has a visible card, grouped by the epic's status in
 * LANE_GROUPS order, then by epic priority and title, with "No epic" last. Epics and
 * milestones are never cards; only epics are lanes.
 *
 * Each lane splits into one row per feature with a visible descendant, holding the
 * feature's card and every card whose nearest feature it is, then an "Other" row for
 * the rest. A feature with no visible descendant is a plain card in its parent's row.
 *
 * Archiving hides cards, not lanes or rows: an archived epic still heads the lane of
 * any unarchived descendants, and an archived feature still heads its row, as context.
 *
 * `matches`, when given, narrows the cards to those ids, plus every card in the lane of
 * a matching epic or the row of a matching feature. Lanes and rows still come from
 * every bean, so a matching card stays under its epic and feature whether or not they
 * matched; a row's unmatched feature is shown as context.
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

  // Epic key → feature key (null for "Other") → placed cards.
  const groups = new Map<string | null, Map<string | null, BoardBean[]>>();
  for (const bean of beans) {
    if (CONTAINER_TYPES.has(bean.type) || !visible.has(columnOf(bean))) continue;
    if (bean.archived && !showArchived) continue;
    const epicKey = nearestEpic(bean, byId)?.id ?? null;
    const featureKey = nearestFeature(bean, byId)?.id ?? null;
    if (
      matches &&
      !matches.has(bean.id) &&
      !(epicKey !== null && matches.has(epicKey)) &&
      !(featureKey !== null && matches.has(featureKey))
    ) {
      continue;
    }
    let lane = groups.get(epicKey);
    if (!lane) groups.set(epicKey, (lane = new Map()));
    const row = lane.get(featureKey);
    if (row) row.push(bean);
    else lane.set(featureKey, [bean]);
  }

  const toCells = (cards: BoardBean[], lead: BoardBean | null): Cell[] =>
    columns.map((column) => {
      const sorted = cards.filter((card) => columnOf(card) === column).sort(byPriorityThenUpdated);
      return { column, cards: lead && columnOf(lead) === column ? [lead, ...sorted] : sorted };
    });

  const lanes: Lane[] = [];
  for (const [epicKey, laneGroups] of groups) {
    const epic = epicKey === null ? null : (byId.get(epicKey) ?? null);
    const placed = new Set([...laneGroups.values()].flat().map((card) => card.id));
    // A feature heading a row leads it, rather than sitting in its parent's row too.
    // One in a hidden column heads nothing, since its card could not lead the row;
    // its cards fall to "Other".
    const heads = new Set(
      [...laneGroups.keys()].filter(
        (key): key is string => key !== null && visible.has(columnOf(byId.get(key)!)),
      ),
    );
    const cardsOf = (key: string | null) =>
      [...laneGroups.entries()]
        .filter(([group]) => (key === null ? group === null || !heads.has(group) : group === key))
        .flatMap(([, cards]) => cards)
        .filter((card) => !heads.has(card.id));

    const rows: Row[] = [...heads]
      .map((key) => byId.get(key)!)
      .sort((a, b) => groupRank(columnOf(a)) - groupRank(columnOf(b)) || byPriorityThenTitle(a, b))
      .map((feature) => ({
        feature,
        featureIsContext: !placed.has(feature.id),
        cells: toCells(cardsOf(feature.id), feature),
        collapsedByDefault: TERMINAL.has(columnOf(feature)),
      }));
    const other = cardsOf(null);
    if (other.length > 0 || rows.length === 0) {
      rows.push({
        feature: null,
        featureIsContext: false,
        cells: toCells(other, null),
        collapsedByDefault: false,
      });
    }

    lanes.push({
      epic,
      group: epic === null ? NO_EPIC_GROUP : columnOf(epic),
      rows,
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

function isContext(row: Row, card: BoardBean): boolean {
  return row.featureIsContext && card.id === row.feature?.id;
}

/** Placed cards per visible column across the lane's rows, leaving out context cards. */
export function columnCounts(lane: Lane): number[] {
  return lane.rows[0].cells.map((_, index) =>
    lane.rows.reduce(
      (sum, row) => sum + row.cells[index].cards.filter((card) => !isContext(row, card)).length,
      0,
    ),
  );
}

export function laneCount(lane: Lane): number {
  return columnCounts(lane).reduce((sum, count) => sum + count, 0);
}

export interface Progress {
  done: number;
  total: number;
}

/**
 * Feature id → its non-scrapped descendants and how many of those are completed, by
 * effective status, over every bean whatever the toggles and search show. Features
 * with no such descendant are absent.
 */
export function progress(beans: readonly BoardBean[]): Map<string, Progress> {
  const byId = new Map(beans.map((bean) => [bean.id, bean]));
  const counts = new Map<string, Progress>();
  for (const bean of beans) {
    const column = columnOf(bean);
    if (CONTAINER_TYPES.has(bean.type) || column === SCRAPPED) continue;
    // Stops at an epic, as nearestFeature does, so a feature counts only its own lane's work.
    for (const ancestor of ancestors(bean, byId)) {
      if (ancestor.type === "epic") break;
      if (ancestor.type !== "feature") continue;
      const count = counts.get(ancestor.id) ?? { done: 0, total: 0 };
      count.total += 1;
      if (column === "completed") count.done += 1;
      counts.set(ancestor.id, count);
    }
  }
  return counts;
}
