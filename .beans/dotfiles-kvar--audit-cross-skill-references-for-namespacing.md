---
# dotfiles-kvar
title: Audit cross-skill references for namespacing
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:18:09Z
updated_at: 2026-08-02T12:18:09Z
parent: dotfiles-gq4t
blocked_by:
    - dotfiles-e4zf
---

Claude Code namespaces plugin skills, so `brainstorming` is now invoked as `df-base:brainstorming`. Any skill body that tells the agent to invoke another skill by bare name is now pointing at a name that does not resolve under Claude Code — while remaining correct for Codex and Cursor, which still get flat skills.

**Files:**
- Modify: whichever files under `home/lib/ai/skills/**/SKILL.md` the audit turns up

- [ ] **Step 1: Find every cross-skill reference**

```bash
grep -rn -E "(invoke|use|hand off to|handoff to|call) (the )?\`?[a-z-]+\`? skill" home/lib/ai/skills/
grep -rn -E "Skill\(|skills/[a-z-]+" home/lib/ai/skills/
```

Known instances to check specifically: `brainstorming/SKILL.md` ends by invoking `writing-plans` and references the local `plannotator:user-code-review` skill; `writing-plans/SKILL.md` refers back to the brainstorming flow.

- [ ] **Step 2: Decide the fix per reference**

For each hit, choose one of:

- **Leave it.** Prose that names a skill descriptively ("the brainstorming flow") needs no change.
- **Make it variant-specific.** Where the instruction is an actual invocation, the `cc:`-prefixed frontmatter mechanism does not help — it filters frontmatter keys, not body text. Prefer wording that works in both worlds: "invoke the `writing-plans` skill (`df-base:writing-plans` in Claude Code)".

Do not restructure the skills; this is a rename audit only.

- [ ] **Step 3: Verify the rendered skills still parse**

Run: `nix build .#checks.x86_64-linux.plugin-validate --no-link -L`

Expected: passes — validation reads frontmatter, so a malformed edit to a `SKILL.md` header surfaces here.

- [ ] **Step 4: Spot-check one rendered skill**

Build the `df-base` plugin path (as in the earlier tasks) and:

```bash
grep -n "writing-plans" $P/skills/brainstorming/SKILL.md
```

Expected: the reference reads as decided in Step 2.

- [ ] **Step 5: Commit**

```bash
git add home/lib/ai/skills
git commit -m "home/lib/ai: fix cross-skill references for plugin namespacing

Plugin skills are invoked as df-base:<name> under Claude Code.

Bean: dotfiles-kvar"
```
