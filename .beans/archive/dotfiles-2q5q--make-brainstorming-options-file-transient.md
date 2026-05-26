---
# dotfiles-2q5q
title: Make brainstorming options file transient
status: completed
type: task
priority: normal
created_at: 2026-05-24T15:01:44Z
updated_at: 2026-05-24T15:06:14Z
---

The brainstorming skill currently writes both an options file and a spec file to docs/specs/, and both end up committed. The options file should be transient — only the spec is worth retaining long-term.

## Summary of Changes

Updated `home/lib/ai/skills/brainstorming/SKILL.md` so the `approved` branch of the Options review now deletes the options file (`rm -f <path>`) before moving on to the design walkthrough. Added a one-sentence rationale: the options file is a transient review artifact; only the spec is worth retaining.

No changes to the `annotated` or `dismissed` branches (both still need the file on disk to iterate). No changes to the Final-spec review path. Historical committed options files in `docs/specs/` were left alone per user direction; cleanup of those is out of scope.
