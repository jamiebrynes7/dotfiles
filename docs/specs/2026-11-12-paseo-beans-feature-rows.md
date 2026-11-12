# Feature rows on the beans board — spec

Date: 2026-11-12

This spec splits each epic lane on the beans plugin's board (`ts/paseo-plugin-beans/`) into one row
per feature, so you can see which tasks belong to which feature. It builds on
`docs/specs/2026-11-05-paseo-beans-plugin.md` and `docs/specs/2026-11-10-paseo-beans-board-search.md`,
and replaces neither.

## Problem

Inside an epic lane, every non-container bean is one flat list of cards sorted into status
columns. When a feature and its tasks are in different states, they land in different columns
next to unrelated cards, and no card shows its parent. This repo has 109 tasks whose parent is a
feature, against 35 tasks that sit directly under an epic. So most of the board has this problem.

## Goals

- Show at a glance which cards belong to which feature, even when their statuses differ.
- Keep the feature itself a clickable card that opens its detail, as now.
- Give a one-click "features only" view of the board.
- Show each feature's progress (done / total) without opening it.

## Non-goals

- **No editing.** The board stays read-only, as the original spec set out.
- **No layout toggle.** Feature rows replace the flat lane layout. You can't switch back to
  the flat view.
- **No parent chips on cards.** The row a card is in already shows its feature.
- **No collapsing of the "Other" row.**

## Design

### Rows

Each epic lane, including "No epic", is split into **rows**:

- **Feature rows.** Every bean is assigned to its **nearest feature ancestor** below the lane's
  epic (bugs and tasks alike). A feature that has at least one visible descendant gets a row of
  its own. The feature's own card sits in **its status column** in that row, as the first card in
  that cell, and is styled to stand out: an accent left edge and the rollup. Its descendants sit
  in their own status columns in the same row. The visibility rules for descendants are the
  scrapped toggle, the archived toggle and search, as today.
- **Other row.** Everything in the lane that has no feature ancestor goes in a final row labelled
  "Other". So do features with no visible descendants, which appear as ordinary cards.
- **A lane with no feature rows** renders exactly as today: one unlabelled row.

Feature rows are ordered the way epic lanes are: by the feature's effective status in
`LANE_GROUPS` order (in progress first), then by priority, then by title. "Other" comes last.
Cards inside a cell keep today's sort (priority, then most recently updated), apart from the
feature card, which comes first.

The columns stay aligned across every row and lane, as they are today: each row's cells have the
same definite widths. The lane still scrolls horizontally as a single unit.

### Rollup

Every feature card with at least one descendant shows **`done/total`**:

- `total` counts the feature's non-scrapped descendants.
- `done` counts those whose effective status (`implicitStatus ?? status`) is `completed`.

It counts every descendant, whatever the search, archive and scrapped toggles show, so the
number doesn't change as you filter. The rollup appears wherever the card is drawn, including
the Other row, where a feature can sit when all its descendants are hidden.

### Context cards

A feature row always shows its feature card, even when the card would otherwise be hidden:

- the feature doesn't match the active search, but one of its descendants does; or
- the feature is archived, the archived toggle is off, and it has unarchived descendants.

In those cases the card is **dimmed** (a context card) but still clickable. Archived epics already
head lanes the same way. Context cards are left out of lane and column counts, so the counts stay
match counts during a search.

### Search

The search follows the same rules for features that it already follows for epics:

- A matching descendant keeps its feature row, with the feature card shown as context.
- A matching feature shows every visible card in its row.
- A matching epic still shows its whole lane.

### Collapsing

- Each feature row has a chevron at its left edge. When a row is collapsed, its feature card
  still shows in its column and every other card in the row is hidden. When every row is
  collapsed, the board shows features only.
- Rows for completed and scrapped features start collapsed, as terminal epic lanes do.
- Collapse state lives in the existing per-tab `collapsed` map, keyed by feature id. Bean ids are
  unique and the "no-epic" key isn't a bean id, so these keys can't clash with lane keys.
  `TabState` needs no schema change.
- While a search is active, rows are held open and their chevrons are hidden, as lanes are today.

### Toolbar: collapse or expand all features

A toolbar button sits beside the toggles:

- When any visible feature row is expanded, the button reads **"Collapse features"**. Pressing it
  writes `collapsed[featureId] = true` for every feature row currently on the board.
- When every row is collapsed, it reads **"Expand features"** and writes `false`.

It writes only to the per-row collapse state, so you can still open a single row afterwards. It
doesn't touch epic lane collapse state. The button is disabled while a search is active. It is
hidden when the board has no feature rows.

### Layout contract (`shared/layout.ts`)

`layout()` stays a pure function of `(beans, showScrapped, showArchived, matches)`. `Lane` drops
its `cells` field in favour of rows:

```ts
interface Row {
  /** The row's feature, or null for "Other" (or a lane's only row). */
  feature: BoardBean | null;
  /** The feature card is shown only as context: dimmed and left out of counts. */
  featureIsContext: boolean;
  /** Cards per visible column, in column order. A feature row's feature card comes first in its cell. */
  cells: { column: string; cards: BoardBean[] }[];
  /** Completed and scrapped features start collapsed; always false for "Other". */
  collapsedByDefault: boolean;
}

interface Lane {
  epic: BoardBean | null;
  group: string;
  rows: Row[];
  collapsedByDefault: boolean;
}
```

The rollup is returned alongside the lanes as `Map<featureId, { done: number; total: number }>`,
so the card component can look it up wherever the card is drawn. The exact return shape (a field
on the result, or a second exported function) is the implementer's call.

Feature lookup walks the parent chain using the same seen-set guard as `nearestEpic`. The walk
stops at the first `feature` it meets, and gives up when it reaches an `epic`, because a feature
above the lane's epic belongs to some other lane.

### RPC and server

There are no changes. `BoardBean` already carries `type`, `parentId`, `status`, `implicitStatus`
and `archived`, which covers everything above.

## Error handling

There are no new failure modes. Everything above is computed on the client from data it already
has. A parent cycle in a bad file is bounded by the seen-set guard. A bean whose parent id points
at a missing bean has no feature ancestor and goes in "Other", the same way it already falls
into "No epic".

## Testing

`shared/layout.test.ts` (run by the existing `paseo-plugin-beans-test` check) covers every rule in
the layout:

- row assignment: nearest feature, and a bug under a feature
- the Other row, including childless features and features whose descendants are all hidden
- row ordering
- the feature card first in its own column
- rollup counts, including scrapped exclusion and implicit completion
- context cards for search and archive
- search rules (descendant match, feature match, epic match)
- default collapse
- a lane with no features

The client rendering (dimming, chevrons, the toolbar button) is checked by hand with
`ts/paseo-demo.sh beans`. If the demo seed has no features with tasks in mixed states, extend it so
it does.
