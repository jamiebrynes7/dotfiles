#!/usr/bin/env bash
# The beans plugin's demo seed, run by ts/paseo-demo.sh (which exports PASEO_HOME):
# a beans project exercising every board and detail state, and a git repo with no
# beans project, both registered as workspaces on the demo daemon. Wipes and
# recreates both directories. Not shipped: ts/default.nix leaves `demo/` out of the
# plugin's source.
set -euo pipefail

project="${BEANS_DEMO_PROJECT:-/tmp/beans-demo-project}"
empty="${BEANS_DEMO_EMPTY:-/tmp/beans-demo-empty}"

commit() { git -c user.name=demo -c user.email=demo@example.com commit -qm "$1"; }
mk() { beans create --json "$@" | jq -r .bean.id; }

rm -rf "$project" "$empty"
mkdir -p "$project" "$empty"
git -C "$empty" init -q

cd "$project"
git init -q
beans init >/dev/null

# Epics in three statuses, so lanes group (in progress, todo, completed) and the
# completed one starts collapsed.
checkout=$(mk "Checkout flow" -t epic -d "Rebuild checkout" -p high -s in-progress)
search=$(mk "Search revamp" -t epic -d "Faster search")
legacy=$(mk "Legacy cleanup" -t epic -d "Old stuff" -s completed)

form=$(mk "Payment form" -t feature -d "Card entry" --parent "$checkout" -s in-progress --tag ui)
luhn=$(mk "Validate card numbers" -t task --parent "$form" -p critical --tag payments --tag security \
  -d "$(cat <<'BODY'
## Notes

Card numbers are checked with the **Luhn** algorithm before we call the processor.

- [x] Strip spaces and dashes
- [ ] Reject numbers shorter than 12 digits
- [ ] Show an inline error under the field

```ts
luhn("4242 4242 4242 4242") // true
```
BODY
)")
mk "3-D Secure challenge" -t task -d "SCA" --parent "$form" --blocked-by "$luhn" \
  --tag payments --tag compliance >/dev/null
mk "Order summary panel" -t task -d "Totals" --parent "$checkout" -s completed >/dev/null

mk "Index product titles" -t task -d "Index" --parent "$search" --tag backend >/dev/null
mk "Typeahead UI" -t feature -d "UI" --parent "$search" -s draft -p low --tag ui --tag frontend >/dev/null
mk "Try Elasticsearch" -t task -d "Spike" --parent "$search" -s scrapped >/dev/null

mk "Remove old cart" -t task -d "Old" --parent "$legacy" -s completed >/dev/null
# Todo under a completed epic: files in Completed, since the inherited status wins.
mk "Delete legacy flags" -t task -d "Flags" --parent "$legacy" >/dev/null

mk "Fix flaky CI" -t bug -d "Flaky" -p high --tag ci --tag flaky >/dev/null
mk "Update README" -t task -d "Docs" -s in-progress -p deferred >/dev/null

git add -A
commit "seed beans"

for dir in "$project" "$empty"; do
  paseo workspace create --isolation local --path "$dir" \
    --title "$(basename "$dir")" --json | jq -r '"workspace \(.workspaceId // "?"): \(.cwd // .name)"'
done
beans list
