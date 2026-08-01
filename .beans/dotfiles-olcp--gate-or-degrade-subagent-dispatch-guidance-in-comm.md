---
# dotfiles-olcp
title: Gate or degrade subagent-dispatch guidance in comment-cleanup for Cursor/Codex
status: todo
type: task
priority: low
created_at: 2026-08-01T20:35:24Z
updated_at: 2026-08-01T20:35:24Z
---

The comment-cleanup skill now has a '## Delegating the judgment pass' section that tells the agent to dispatch a subagent. The skill has no variant gating in its frontmatter, so mkSkillFiles deploys it to Cursor (~/.cursor) and Codex (~/.codex/skills) as well as Claude Code, and those runtimes may not expose a subagent/Task tool.

Two options:
- Add a one-line degradation to the section: where subagent dispatch is unavailable, apply the criteria directly with the default-to-removal disposition.
- Gate the section with a `cc:` variant key so it only reaches Claude Code.

Surfaced by the subagent review on dotfiles-dcyv; deferred as orthogonal to that bean's scope.
