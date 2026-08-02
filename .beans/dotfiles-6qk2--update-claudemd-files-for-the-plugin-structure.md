---
# dotfiles-6qk2
title: Update CLAUDE.md files for the plugin structure
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:18:09Z
updated_at: 2026-08-02T12:18:09Z
parent: dotfiles-gq4t
blocked_by:
    - dotfiles-36nb
---

The two CLAUDE.md files describe a structure this epic replaces: `home/lib/ai/CLAUDE.md` documents `mkSkillFiles` and the `skillsDirs` contract as the way skills reach assistants, and the root `CLAUDE.md` project-structure block has no `checks/` or `home/lib/ai/plugins/` entry. Both are load-bearing context for future sessions.

**Files:**
- Modify: `home/lib/ai/CLAUDE.md`
- Modify: `CLAUDE.md`

- [ ] **Step 1: Rewrite `home/lib/ai/CLAUDE.md`**

Update these sections; keep the existing Purpose / Structure / Contracts / Key Decisions / Invariants / Gotchas shape:

- **Freshness**: set to the date this lands.
- **Structure**: add `plugins/` with `module.nix` (options), `base.nix` (the `df-base` declaration), `default.nix` (`mkPluginFiles`), `hook-types.nix` (moved from the claude-code module).
- **Contracts**: state that `dotfiles.ai.plugins.<name>` is the single declaration point; that `mkPluginFiles { variant, targetDir, plugins }` returns `{ files, conflicts }` and installs to `<targetDir>/df-<name>`; that `mkSkillFiles` now serves only Codex and Cursor, which flatten every enabled plugin's `skillDirs`.
- **Key Decisions**: record that plugins are skills-directory plugins (`df-<name>@skills-dir`) rather than a marketplace — discovery is in place, so there is no registration, no trust prompt and no cache to invalidate; and that the `df-` prefix is fixed because per-project `enabledPlugins` entries reference it forever.
- **Gotchas**: plugin skills are namespaced (`df-base:brainstorming`) under Claude Code but flat under Codex/Cursor; `defaultEnabled` needs Claude Code ≥ 2.1.154; plugins cannot carry permission allowlists, so those stay on the program modules.

- [ ] **Step 2: Update the root `CLAUDE.md`**

- **Freshness**: set to the date this lands.
- **Project Structure** block: add `checks/` (the `home-eval` module) and `home/lib/ai/plugins/`.
- **Commands**: note that `nix flake check` now also evaluates a home-manager configuration and validates the rendered plugins.
- **Conventions**: add a short "Plugin pattern" subsection next to "Program module pattern", showing a minimal `dotfiles.ai.plugins.<name>` declaration and pointing at `home/lib/ai/CLAUDE.md` for detail.

- [ ] **Step 3: Verify the described structure matches reality**

```bash
ls home/lib/ai/plugins checks
grep -n "skillsDirs" home/lib/ai/CLAUDE.md
```

Expected: the directory listings match what the docs claim, and `skillsDirs` appears only where it is described as the Codex/Cursor-internal flattening argument — not as a module option.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md home/lib/ai/CLAUDE.md
git commit -m "docs: describe the plugin structure

Bean: dotfiles-6qk2"
```
