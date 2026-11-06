---
# dotfiles-na0t
title: Add a retro skill for session retrospectives
status: completed
type: feature
priority: normal
created_at: 2026-10-07T15:57:30Z
updated_at: 2026-11-06T10:45:21Z
---

Add a user-invoked `retro` skill under `home/lib/ai/skills/`. It reviews a coding session and reports what in the agent's setup should change so future runs go better. The output is a report for the user to read; the skill doesn't edit anything itself.

Adapted from mattpocock's `retro` skill (https://github.com/mattpocock/skills/blob/main/skills/engineering/retro/SKILL.md). Ours differs as listed below.

## Keep from upstream

- User-invoked only (`disable-model-invocation: true`), so it adds no always-loaded description.
- Defaults to the current session; otherwise reads the session the user names.
- The categories, each with a "use when" tied to evidence from the session: navigation, automated checks, coding standards, global instructions, tool economy, instructions that change nothing, information access.
- Mechanical violations (fixed patterns, banned APIs, import shapes, file-location rules) get a check, not a written rule: a lint rule, pre-commit hook or CI job. Look first for an existing check that's unwired or broken before proposing a new one. A repo with no guardrail at all is itself a finding.
- Coding standards belong with the reviewer rather than the implementer, because the implementer's context is the more crowded one.
- Present findings in order of severity.

## Differences from upstream

- **Don't assume upstream's file layout** (`CODING_STANDARDS.md`, nav-pointer-only CLAUDE.md). Point each finding at wherever that kind of guidance already lives in the setup being reviewed.
- **Say where each fix lands, in general terms:** project-level (the repo's CLAUDE.md/AGENTS.md, project skills, its checks) versus user-level (user skills, global instructions). Don't refer to the dotfiles repo or any particular way of managing user-level config.
- **Don't load a writing skill.** The output is a report, not a directive.
- **Ending:** after presenting the report, offer to track the findings the user accepts. Choose how from what the project uses (beans, GitHub issues, a TODO file, nothing). Don't assume beans.
- **Session logs:** the current session is already in context. Past sessions mean reading large log files whose location depends on the tool, so hand that reading to a subagent.

## Todo

- [x] Write `home/lib/ai/skills/retro/SKILL.md` (aim for ~50–60 lines), with variant-prefixed frontmatter where the assistants differ.
- [x] Check that `disable-model-invocation` comes through `process-frontmatter` correctly for each variant (and what Cursor/Codex do with it).
- [x] Find out where Claude Code and Codex store session logs, so the skill can name them per variant or describe them generally.
- [x] Run it once on a real session and adjust.

## Summary of Changes

Added `home/lib/ai/skills/retro/`, a user-invoked skill adapted from mattpocock's `retro` (MIT, attributed in the skill's `LICENSE`). It gathers evidence from the current or a named past session, sorts candidates into the upstream categories, says whether each fix lands project- or user-level, reports by severity, and offers to track accepted findings in whatever the project uses.

- User-invoked only: `cc:`/`cursor:disable-model-invocation: true` (both honour it). Codex ignores that key and instead reads `agents/openai.yaml` `policy.allow_implicit_invocation: false`, which ships in the skill dir. I checked the built output for all three variants.
- Session log locations are listed for Claude Code (`~/.claude/projects/<cwd-slug>/<id>.jsonl`), Codex (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`) and Cursor (`~/.cursor/projects/<slug>/agent-transcripts/`). Past-session reading goes to a subagent that parses the JSONL.
- A trial run on a real dotfiles session produced a useful report. Its feedback, together with a critical review, shaped the final version: a tighter No-ops trigger (applied but made no difference), "no review step" counted as a finding, a severity rubric, a check against the current state, a fallback after compaction, and the evidence list the log subagent is asked for.
- Renamed the "Global instructions" category to "Always-loaded instructions", since it covers project files too and "global" clashed with "user-level".
