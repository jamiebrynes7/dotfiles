#!/usr/bin/env bash
# The agent-status plugin's demo seed, run by ts/paseo-demo.sh (which exports
# PASEO_HOME): real Claude agents, each told to make one set_status call, covering
# every link kind and the card with no links, a wrapped summary, and no waiting_on.
# Each run spends one short model turn per agent. Not shipped: ts/default.nix leaves
# `demo/` out of the plugin's source.
set -euo pipefail

dir="${AGENT_STATUS_DEMO_DIR:-/tmp/agent-status-demo}"
rm -rf "$dir"
mkdir -p "$dir"
git -C "$dir" init -q
workspace=$(paseo workspace create --isolation local --path "$dir" --title "$(basename "$dir")" --json | jq -er .workspaceId)

seed() {
  local title=$1 args=$2
  paseo run --no-wait --quiet --provider claude/claude-haiku-5-5 --workspace "$workspace" --cwd "$dir" --title "$title" \
    "This is a UI demo. Call the set_status tool exactly once, with exactly these arguments: ${args}. Make no other tool calls, and then reply with just \"Done.\"" \
    >/dev/null
  echo "started agent: $title"
}

seed "Working, no links" \
  '{"summary": "Refactoring the session store"}'
seed "PR waiting on CI" \
  '{"summary": "Auth test fix pushed", "waiting_on": "CI on #1", "links": [{"kind": "pr", "url": "https://github.com/getpaseo/paseo/pull/1"}]}'
seed "PR and review, waiting on you" \
  '{"summary": "Spec drafted and PR opened for the new sync protocol", "waiting_on": "you: review the spec", "links": [{"kind": "pr", "url": "https://github.com/getpaseo/paseo/pull/2"}, {"kind": "review", "url": "http://localhost:19432/#demo"}]}'
seed "All three kinds, long summary" \
  '{"summary": "Migrated every legacy config loader caller and brought the docs up to date", "waiting_on": "you: merge when happy", "links": [{"kind": "pr", "url": "https://gitlab.com/group/project/-/merge_requests/7"}, {"kind": "review", "url": "http://localhost:19433/"}, {"kind": "other", "url": "https://example.com/docs/config/?ref=demo"}]}'
