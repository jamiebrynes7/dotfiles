# Text search on the beans board — spec

Date: 2026-11-10

Adds a search box to the beans plugin's board panel (`ts/paseo-plugin-beans/`). Typing in it
narrows the board to the beans that the `beans` CLI's own full-text search matches. It
builds on `docs/specs/2026-11-05-paseo-beans-plugin.md`, and replaces none of it.

## Goals

- Filter the board by text and see only matching cards, within about a second of typing.
- Keep the results current while agents edit beans, the same way the unfiltered board is.

## Non-goals

- **No matching on the bean id.** The CLI's search does not index ids. It indexes the slug,
  which is the id's title part, and a bean whose body mentions an id still matches.
- **No search syntax of our own.** The query goes to the CLI verbatim, so whatever its search
  supports (and nothing else) is what the box supports.
- **No search in the detail panel**, and no highlighting of where a match occurred.
- **No persistence.** The query is not saved in the tab state.

## Facts this design depends on

Checked against the `beans` CLI in `packages/beans` on 2026-11-10:

1. `BeanFilter.search: String` is a Bleve full-text query over the slug, title and body.
   It matches whole words (`plannot` finds nothing, `plannot*` finds matches) and supports
   `term~` fuzzy matching, `pre*` wildcards, `AND`/`OR`, and the `slug:`, `title:` and
   `body:` field prefixes. The query goes verbatim to `bleve.NewQueryStringQuery`
   (`internal/search/index.go`). The id is indexed too, as an exact, case-sensitive
   keyword outside the default search: only `id:<full id>`, `id:*<suffix>` or a
   `/regexp/` finds it. Tags are not indexed.
2. Archived beans are included in search results.
3. Some malformed syntax returns an empty list (`title:((`, `a AND`). Text that Bleve's
   parser rejects fails the CLI instead, with `Error: graphql: <reason>` on stderr: a
   field prefix with no term (`title:`, `:`) gives `syntax error`, an unclosed quote or a
   bad fuzziness gives `parse error: …`, and a bad `/regexp/` gives
   `error parsing regexp: …`. A GraphQL error in our own fixed query reads differently
   (`Expected Name, found <EOF>`).
4. An empty `search` string matches every bean.
5. A search query over this repo (274 beans) takes about 0.3 s.

## Design

### RPC contract (`shared/rpc.ts`)

`beans.board` gains an optional input and an extra output field:

```ts
input:  { workspaceId: string; search?: string }
output: { kind: "none"; directory }
      | { kind: "project"; fingerprint; beans: BoardBean[];
          matches: string[] | null; searchError: string | null }
```

`matches` lists the ids that the search matched. It is `null` when no search was given. The
client omits `search` when the box is blank or whitespace-only (fact 4). The server treats a
blank string the same way, as defence in depth. `beans` is always the full list, whatever
the search, because the layout still needs every bean to find a card's epic and to head
lanes with archived epics. `searchError` is the parser's reason when the CLI rejected the
search text (fact 3), in which case `matches` is `[]`. Otherwise it is `null`.

### Server (`server/board.ts`)

The board read stays a single `beans graphql` call, and both query strings stay fixed. With
a search it adds an aliased `matches: beans(filter: { search: $search }) { id }` next to the
existing `blocked` alias, and the text reaches the CLI only as the `$search` variable. With
no search it runs the current query unchanged and returns `matches: null`. The fingerprint
is still taken before the query. So the existing poll covers search too: when a bean
changes, the next tick refetches the board, and the refetch re-runs the same search.

When the searched read fails with one of fact 3's parse errors, the server runs the plain
board query and returns its beans with `matches: []` and `searchError`. The client then
still has the full list, so clearing the box restores the board at once. Any other
failure, or a parse error on an unsearched read, stays an RPC error.

A project with no data directory returns `beans: []` and, when a search was given,
`matches: []` (otherwise `null`).

### Client

- **Search box.** A `TextInput` from `react-native` sits in the board toolbar beside the
  toggles. It has a clear button and a `Search beans` placeholder. Its value is plain
  component state. A small muted line under it lists the operators (whole words, `log*`,
  `login~`, `AND`, `OR`, and the `title:`, `body:`, `slug:` and `id:` prefixes). While the
  current result has a `searchError`, that line shows "Can't parse search: <reason>" in
  the danger colour instead.
- **Debounce.** 300 ms after typing stops, the trimmed text becomes the active query, and
  `useBoard` passes it to `beans.board`. Clearing the box applies at once, with no debounce.
- **No blanking.** A new query keeps the current board on screen until its result arrives.
  The Loading state is only for the first load. A result is shown only for the current
  query: a response for an earlier query that is still in flight is discarded. A failed
  search shows the existing error banner over the last board, as poll errors already do.
- **Layout.** `layout()` takes the match set, or `null`. When it gets a set, only the cards
  in it are placed, plus every card in the lane of an epic that matched. Epics are never
  cards, so a search for an epic's title shows its lane. Epic lanes still come from all
  beans, and a lane with no matching card is dropped, as a lane with no visible card
  already is. The Show scrapped and Show
  archived toggles apply on top of the matches.
- **Lanes while searching.** While a query is active, every remaining lane is shown
  expanded, whatever its saved or default collapsed state. While searching, lane headers
  do not toggle and hide their chevron, so a press never changes the saved state out of
  sight. That state comes back when the search is cleared.
  Lane and column counts show match counts, because they count the placed cards.
- **Empty result.** With a query active and no lanes left, the board says "No beans match"
  instead of "Nothing to show". So does a search the CLI could not parse. A match that
  the scrapped or archived toggle hides also reads as "No beans match", deliberately.

## Error handling

- A CLI failure or timeout during a search reaches the client as an RPC error and shows in
  the existing banner with Retry. The previous board stays visible.
- A search Bleve cannot parse is not an RPC error: it comes back as `searchError` and shows
  under the box, with no banner (fact 3). Half-typed queries like `title:` hit this
  constantly.
- The `search` input is a plain Zod string. It never reaches the query text, so it needs no
  character fence. A 500-character cap keeps an absurd paste off the
  command line.

## Testing

- `server/board.test.ts` (the existing fake-`beans` harness): with a search, the read passes
  `search` as a `-v` variable and maps the aliased `matches`. With none, it runs the
  unchanged query and returns `matches: null`. A blank search counts as no search. A
  missing data directory with a search returns `matches: []`. Each of fact 3's parse errors
  becomes a `searchError` with the full bean list. Any other failure, or a parse error
  without a search, still rejects.
- `shared/layout.test.ts`: a match set places only matching cards, keeps the epic lanes of
  matching descendants (archived epics included), keeps the whole lane of a matching epic,
  drops lanes with no matches, and still honours the scrapped and archived toggles.
- The client behaviour (debounce, no blanking, forced expansion) has no test harness. Verify
  it by hand with `ts/paseo-demo.sh beans`.
