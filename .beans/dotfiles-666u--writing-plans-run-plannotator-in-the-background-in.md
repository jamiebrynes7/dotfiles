---
# dotfiles-666u
title: 'writing-plans: run plannotator in the background instead of a 30-minute timeout'
status: todo
type: task
priority: low
created_at: 2026-10-11T16:25:55Z
updated_at: 2026-10-11T16:25:55Z
---

Mirror the brainstorming change from dotfiles-cs7q in `home/lib/ai/skills/writing-plans/SKILL.md`: where it says to set a 30-minute Bash timeout for the plannotator breakdown review, run the command in the background when the shell tool notifies on exit (allowing at least 30 minutes), falling back to a 30-minute foreground timeout otherwise. The skill also deploys to Cursor and Codex, so keep the wording tool-agnostic.

## Acceptance criteria

- [ ] writing-plans' plannotator instruction prefers a background run with exit notification, with the timeout as the fallback
