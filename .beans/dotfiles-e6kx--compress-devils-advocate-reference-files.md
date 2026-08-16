---
# dotfiles-e6kx
title: Compress devils-advocate reference files
status: completed
type: task
priority: normal
created_at: 2026-08-15T15:33:00Z
updated_at: 2026-08-16T09:24:03Z
parent: dotfiles-nj63
blocked_by:
    - dotfiles-nw9f
---

**Files:** `home/lib/ai/skills/devils-advocate/` (117 + 1,068 reference lines → ~400 total)

Lowest-confidence item in the epic: the references are already progressively disclosed, so always-loaded cost is only 117 lines. Reduce the exposition, keep the calibration.

Keep untouched:

- [x] SKILL.md calibration — the 7-concern cap, honest-severity definitions, the "so what?" test, steel-man-first. Calibration is exactly what a model cannot supply for itself
- [x] `references/ai-blind-spots.md` (326 lines) — the one reference that is not generic, and the most directly default-counteracting content in the repo

Compress:

- [x] `references/questioning-frameworks.md` (405 → ~80) — naming pre-mortem, inversion, and Socratic probing carries the value; explaining Five Whys and Six Thinking Hats at length does not
- [x] `references/blind-spots.md` (337 → ~80) — keep the 11 categories as a checklist, cut the exposition

- [ ] Run `nix flake check`

## Summary of Changes

Compressed the two generic devils-advocate references; kept the calibration untouched.

- `references/questioning-frameworks.md` (405 → 97): steel-manning, pre-mortem, inversion, the six Socratic probes, and reverse five whys survive as their operative move plus their question banks — which is where the value is. The long expositions of Five Whys and Six Thinking Hats are gone; the useful hats (missing data, alternatives, process) remain as a short 'other lenses' list.
- `references/blind-spots.md` (337 → 48): all 11 categories kept as a checklist — lead question plus the concrete misses to look for — with the 'Why It's Missed' exposition and per-category question tables cut.
- `SKILL.md` and `references/ai-blind-spots.md` calibration untouched, except one pointer line that still advertised 'Six Thinking Hats' as a named section.
