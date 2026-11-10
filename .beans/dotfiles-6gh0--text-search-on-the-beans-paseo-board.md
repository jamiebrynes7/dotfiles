---
# dotfiles-6gh0
title: Text search on the beans paseo board
status: completed
type: task
priority: normal
created_at: 2026-11-10T09:27:03Z
updated_at: 2026-11-10T10:06:17Z
---

**Spec:** `docs/specs/2026-11-10-paseo-beans-board-search.md` — whole spec

## What to build

A search box in the beans board panel's toolbar. Typing a query narrows the board to the beans the `beans` CLI's full-text search matches (slug, title, body; CLI syntax passed through verbatim), applied 300 ms after typing stops and cleared instantly. While a query is active, lanes with matches are shown expanded and lanes without matches are hidden; the scrapped/archived toggles still apply; results stay fresh through the existing fingerprint poll. The query is transient component state.

## Acceptance criteria

- [x] `beans.board` accepts an optional `search` (max 500 chars) and returns `matches: string[] | null` alongside the full bean list — `null` with no search, blank/whitespace treated as no search
- [x] With a search, the board read is still one `beans graphql` call whose query text is fixed; the search text reaches the CLI only as a `-v` variable (covered in the board server tests)
- [x] A project with no data directory returns `matches: []` when searched, `null` otherwise (covered in the board server tests)
- [x] `layout()` given a match set places only matching cards, keeps the epic lanes of matching descendants (archived epics included), drops lanes with no matches, and still honours the scrapped/archived toggles (covered in layout tests)
- [x] In `ts/paseo-demo.sh beans`: typing `plannot*` narrows the board after ~300 ms; clearing restores it immediately; the board does not flash Loading between queries
- [x] While searching, a match inside a completed epic's lane (collapsed by default) is visible; clearing the search restores saved collapse state
- [x] A query with no matches, or malformed syntax like `title:((`, shows "No beans match"
- [x] A response for a superseded query never replaces the current query's result

## Constraints

- The search query is never spliced into the GraphQL text; both query strings stay fixed.
- The unsearched board read stays the current query, unchanged.
- The existing tab-state shape still parses (no new persisted field).

## Summary of Changes

The beans board has a search box. Its text goes verbatim to the `beans` CLI's Bleve full-text search (slug, title, body; `id:` for exact id lookup), 300 ms after typing stops. Clearing the box takes effect at once.

- `beans.board` takes an optional `search` (capped at 500 characters). It returns the full bean list plus `matches` (ids, or null) and `searchError`, all from one CLI call, so the fingerprint poll keeps results fresh. The search text reaches the CLI only as a `-v` variable.
- A search that Bleve's parser rejects (`title:`, an unclosed quote, a bad fuzziness or regexp) fails the CLI. The server recognises that stderr, falls back to the plain board read, and returns the reason as `searchError`. The hint line shows it, not the error banner.
- `layout()` takes the match set. It places only matching cards, plus every card in a matching epic's lane, and drops lanes with no matches. The scrapped and archived toggles still apply.
- While searching, lanes are held open and their headers do not toggle. `usePolled` gained a `scope`, so a new query keeps the board on screen until its result arrives, and a superseded query's response is still dropped.
- A muted line under the box lists the operators.
- The spec now records what was built: fact 3 corrected, epic-lane matches, the lane toggle, and `searchError`.

Tested with new cases in the board and layout suites (44 pass) and by hand in `ts/paseo-demo.sh beans`.
