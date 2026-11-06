---
name: retro
description: Conduct a retrospective on a coding session, reporting what in the agent's setup should change so future runs go better.
cc:disable-model-invocation: true
cursor:disable-model-invocation: true
---

# Retro

Review a coding session and suggest changes to the agent's **environment** (instructions, skills, checks, tooling) so future runs go better. The output is a report for the user. Edit nothing, except in step 5, and only for findings the user accepts.

## Steps

1. **Gather evidence.** Default to the current session, which is already in your context. If earlier parts of it were compacted away, or the user names a past session, read the log instead. Logs are large, tool-specific JSONL files, so:
   - Find the file yourself, by id, or by project and date plus a grep for the topic. Typical locations:
     - Claude Code: `~/.claude/projects/<cwd, with / and . replaced by ->/<session-id>.jsonl`
     - Codex: `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`
     - Cursor: `~/.cursor/projects/<path-slug>/agent-transcripts/<session-id>/`
   - Hand the path to a subagent, and tell it to parse the file with `jq` or a script rather than read it raw. If no subagent is available, grep the log; never read it whole.
   - Ask for evidence with record indices or timestamps:
     - user corrections, quoted;
     - wrong turns, slow searches, and mistakes;
     - expensive tool calls, in output size or in wall-clock time;
     - missing information;
     - which instructions and skills were loaded, followed or ignored;
     - whether a review step ran, and what it caught.

2. **Collect candidates.** Each candidate cites evidence from the session.
   - **Navigation:** finding the right file was slow, or a hidden dependency between files tripped the agent up. Add a pointer where the agent looked first.
   - **Automated checks:** the agent made a mistake a lint, type check, test or hook could have caught. Read the repo's own check commands and CI first: a check that exists but is unwired or silently broken is the finding, not a new check. A repo with no guardrail at all (no pre-commit hook, no CI running its checks) is itself a finding.
   - **Coding standards:** a review missed a mistake, or there was no review. A *mechanical* violation (a fixed pattern, a banned API, an import shape, a file-location rule) gets a deterministic check, not a written rule. Keep written rules for judgement calls, and put them in what the *reviewer* reads, not the implementer: the implementer's context is the more crowded one. A project with no review step or standards is itself a finding.
   - **Always-loaded instructions:** project or user-level instructions that load into every session are large, or hold rules that belong in a check, a reviewer's standards, or a file that only loads where it applies.
   - **Tool economy:** a tool call was expensive (huge output, repeated reads, an inefficient CLI or MCP, a long blocking run) and could be streamlined.
   - **No-ops:** an instruction applied in this session but made no difference, because it was ignored or the agent would have done that anyway. An instruction that simply didn't come up is not evidence. If a skipped instruction hurt the outcome, treat it as a discoverability problem instead.
   - **Information access:** the agent lacked something crucial, such as server logs, read-only access to a service, docs, or permission facts.

   Check each candidate against the setup as it is now: a past session may already have fixed it.

3. **Say where each fix lands.** It is either *project-level* (the repo's CLAUDE.md, AGENTS.md or `.cursor/rules`, project skills, its checks and CI, its agent settings) or *user-level* (user skills, global instructions, user settings). Name the specific file or check where one exists, and otherwise say what is missing. If user-level config is managed from a repo, name the source file, not the deployed copy. Don't assume any particular file layout.

4. **Present the report.** Order findings by severity: things the user had to correct come first, then problems that would recur silently, then things that only cost time. For each finding, give the evidence, the proposed change, and where it lands. Leave out categories with no evidence, and if nothing qualifies, say so. A user correction with no environment fix can go at the end, marked as such.

5. **Offer to track** the findings the user accepts, using whatever the project already uses (an issue-tracker CLI, GitHub issues, a TODO file). If it uses nothing, ask.
