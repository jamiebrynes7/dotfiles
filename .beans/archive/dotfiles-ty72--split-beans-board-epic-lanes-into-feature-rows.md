---
# dotfiles-ty72
title: Split beans board epic lanes into feature rows
status: completed
type: task
priority: normal
created_at: 2026-11-12T09:51:11Z
updated_at: 2026-11-12T10:37:44Z
parent: dotfiles-us8h
---

**Spec:** `docs/specs/2026-11-12-paseo-beans-feature-rows.md` — Rows, Rollup, Context cards, Search, Collapsing, Layout contract, Testing

## What to build

On the board, each epic lane (including "No epic") is split into one row per feature that has visible descendants, followed by an "Other" row for everything without a feature ancestor (and features with no visible descendants). The feature stays a clickable card: accented, first in its own status column within its row, and showing a `done/total` rollup. Its tasks and bugs sit in their status columns in the same row, so a feature and its work read together even when their statuses differ. Rows collapse individually; a collapsed row still shows its feature card. Search and archive treat features the way they already treat epics, with dimmed context cards.

## Acceptance criteria

- [x] A bean is placed in the row of its nearest feature ancestor below the lane's epic; a bug under a feature lands in that feature's row
- [x] A feature with no visible descendants appears as an ordinary card in the "Other" row; a lane with no feature rows renders as a single unlabelled row, as today
- [x] Feature rows are ordered by the feature's effective status (in progress first), then priority, then title; "Other" is last
- [x] The feature card is the first card in its own status column within its row, visually distinguished, and opens the feature's detail when pressed
- [x] Feature cards with descendants show `done/total`, where total excludes scrapped descendants, done counts effective-status `completed` (inherited completion included), and neither changes with search, archive or scrapped toggles
- [x] While searching, a matching descendant keeps its feature row with the non-matching feature card shown dimmed; a matching feature shows every visible card in its row; a matching epic still shows its whole lane
- [x] An archived feature with unarchived descendants and Show archived off still heads its row as a dimmed card
- [x] Dimmed context cards are excluded from lane and column counts
- [x] Each feature row has a header (chevron, title, id, status, rollup) that collapses it to just that header; completed and scrapped features start collapsed; the state survives tab reload; rows are held open with no chevron while searching
- [x] Layout unit tests cover each rule above
- [x] The demo seed includes at least one feature with tasks in mixed states, so `ts/paseo-demo.sh beans` shows feature rows

## Constraints

- Collapse state stays in the existing per-tab `collapsed` map, keyed by feature id; the saved tab state schema does not change.
- No RPC or server changes; the layout stays a pure function of the board data and toggles.
- Columns stay aligned across rows and lanes.

## Summary of Changes

Epic lanes on the beans board now split into one row per feature with visible descendants, plus an "Other" row.

- `layout()` builds `Lane.rows`. Each card is filed under its nearest feature below the lane's epic. A feature in a hidden column heads no row. Archived or unmatched features head their rows as context. New `progress()`, `columnCounts()` and `laneCount()` helpers handle rollups and counts, leaving context cards out.
- The client draws a muted header for each feature row with the chevron, title, id, status and done/total. A collapsed row shows only its header. The feature card leads its status column with a type-coloured edge and the rollup, and context cards are dimmed. Screen-reader labels include the progress and context state.
- The demo seed adds a completed feature, "Guest checkout", and a completed task under "Payment form".
- Layout tests cover row assignment, the epic boundary, nested features, cycles, dangling parents, ordering, rollup, search and archive context, counts and default collapse.

Deviation from the spec (decided during the demo review): a collapsed feature row hides its card as well, and every feature row has a header line instead of a bare chevron in a left gutter.
