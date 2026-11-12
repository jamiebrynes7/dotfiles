---
# dotfiles-ty72
title: Split beans board epic lanes into feature rows
status: todo
type: task
created_at: 2026-11-12T09:51:11Z
updated_at: 2026-11-12T09:51:11Z
parent: dotfiles-us8h
---

**Spec:** `docs/specs/2026-11-12-paseo-beans-feature-rows.md` — Rows, Rollup, Context cards, Search, Collapsing, Layout contract, Testing

## What to build

On the board, each epic lane (including "No epic") is split into one row per feature that has visible descendants, followed by an "Other" row for everything without a feature ancestor (and features with no visible descendants). The feature stays a clickable card: accented, first in its own status column within its row, and showing a `done/total` rollup. Its tasks and bugs sit in their status columns in the same row, so a feature and its work read together even when their statuses differ. Rows collapse individually; a collapsed row still shows its feature card. Search and archive treat features the way they already treat epics, with dimmed context cards.

## Acceptance criteria

- [ ] A bean is placed in the row of its nearest feature ancestor below the lane's epic; a bug under a feature lands in that feature's row
- [ ] A feature with no visible descendants appears as an ordinary card in the "Other" row; a lane with no feature rows renders as a single unlabelled row, as today
- [ ] Feature rows are ordered by the feature's effective status (in progress first), then priority, then title; "Other" is last
- [ ] The feature card is the first card in its own status column within its row, visually distinguished, and opens the feature's detail when pressed
- [ ] Feature cards with descendants show `done/total`, where total excludes scrapped descendants, done counts effective-status `completed` (inherited completion included), and neither changes with search, archive or scrapped toggles
- [ ] While searching, a matching descendant keeps its feature row with the non-matching feature card shown dimmed; a matching feature shows every visible card in its row; a matching epic still shows its whole lane
- [ ] An archived feature with unarchived descendants and Show archived off still heads its row as a dimmed card
- [ ] Dimmed context cards are excluded from lane and column counts
- [ ] Each feature row has a chevron that collapses it to just its feature card; completed and scrapped features start collapsed; the state survives tab reload; rows are held open with no chevron while searching
- [ ] Layout unit tests cover each rule above
- [ ] The demo seed includes at least one feature with tasks in mixed states, so `ts/paseo-demo.sh beans` shows feature rows

## Constraints

- Collapse state stays in the existing per-tab `collapsed` map, keyed by feature id; the saved tab state schema does not change.
- No RPC or server changes; the layout stays a pure function of the board data and toggles.
- Columns stay aligned across rows and lanes.
