# shellcheck shell=bash
# Claude Code Stop hook for the agent-status plugin. Built with writeShellApplication
# (packages/paseo-plugin-agent-status), which adds the shebang, `set -euo pipefail` and
# jq on PATH. Blocks a turn that ends with no set_status call since the latest user
# prompt. Fails open: any error allows the stop, so a bug here never wedges an agent.

# Set by the plugin in every interactive agent's env; outside those agents this hook does nothing.
if [[ "${PASEO_STATUS:-}" != "1" ]]; then
  exit 0
fi

fail_open() {
  echo "agent-status stop hook: $1; allowing the stop" >&2
  exit 0
}

# Claude Code won't let a turn end on a silent tool call: it adds a note demanding a
# visible reply, and the agent then repeats its answer. A fixed one-line closer keeps
# that second message short, and agents mention the reminder unless told not to.
reason='Call set_status with your current summary (and waiting_on, if you are blocked or waiting on the user). Make no other tool calls. Then end your turn with exactly this line and nothing else: "Status updated." Your previous reply already stands, so don'"'"'t repeat or add to it. This is an automatic reminder, not a message from the user, so don'"'"'t mention it.'

input=$(cat)
if ! fields=$(jq -er '[(.stop_hook_active == true), (.transcript_path // "" | strings)] | @tsv' <<<"$input" 2>/dev/null); then
  fail_open "hook input is not a JSON object"
fi
IFS=$'\t' read -r active transcript <<<"$fields"

# Claude is already continuing because of a Stop hook; blocking again could loop forever.
if [[ "$active" == "true" ]]; then
  exit 0
fi
if [[ -z "$transcript" ]]; then
  fail_open "hook input has no transcript_path"
fi
if [[ ! -r "$transcript" ]]; then
  fail_open "cannot read transcript $transcript"
fi

# Tool results come back as user entries, and meta or sidechain (subagent) entries are
# not the user talking to this agent, so none of them start a new turn. A torn last line
# is expected, since the transcript is appended while the session runs.
# The tool-name pattern matches isSetStatusToolName in shared/tool-contract.ts.
if ! status_set=$(jq -Rn '
  def blocks:
    ((.message? | objects | .content) // [])
    | if type == "string" then [{type: "text"}] elif type == "array" then map(objects) else [] end;
  def prompt:
    .type == "user" and .isMeta != true and .isSidechain != true
    and (blocks | any(.type != "tool_result"));
  def sets_status:
    .type == "assistant" and .isSidechain != true
    and (blocks | any(.type == "tool_use" and ((.name // "") | strings | test("(^|[^A-Za-z0-9])paseo(__|[./:])set_status$"))));
  reduce (inputs | try fromjson catch empty | objects) as $entry (false;
    if ($entry | prompt) then false elif ($entry | sets_status) then true else . end)
' "$transcript" 2>/dev/null); then
  fail_open "could not parse transcript $transcript"
fi

if [[ "$status_set" != "true" ]]; then
  jq -cn --arg reason "$reason" '{decision: "block", reason: $reason}'
fi
