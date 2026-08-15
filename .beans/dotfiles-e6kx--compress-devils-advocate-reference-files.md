---
# dotfiles-e6kx
title: Compress devils-advocate reference files
status: todo
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-15T15:33:10Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**Files:** `home/lib/ai/skills/devils-advocate/` (117 + 1,068 reference lines → ~400 total)

Lowest-confidence item in the epic: the references are already progressively disclosed, so always-loaded cost is only 117 lines. Reduce the exposition, keep the calibration.

Keep untouched:

- [ ] SKILL.md calibration — the 7-concern cap, honest-severity definitions, the "so what?" test, steel-man-first. Calibration is exactly what a model cannot supply for itself
- [ ] `references/ai-blind-spots.md` (326 lines) — the one reference that is not generic, and the most directly default-counteracting content in the repo

Compress:

- [ ] `references/questioning-frameworks.md` (405 → ~80) — naming pre-mortem, inversion, and Socratic probing carries the value; explaining Five Whys and Six Thinking Hats at length does not
- [ ] `references/blind-spots.md` (337 → ~80) — keep the 11 categories as a checklist, cut the exposition

- [ ] Run `nix flake check`
