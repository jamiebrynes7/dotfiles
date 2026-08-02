---
# dotfiles-6l44
title: Enable df-beans for this repository
status: todo
type: task
priority: normal
created_at: 2026-08-02T12:17:06Z
updated_at: 2026-08-02T12:17:06Z
parent: dotfiles-u1q7
blocked_by:
    - dotfiles-vjte
---

`df-beans` ships `defaultEnabled = false`, so beans priming is now off everywhere — including in this repository, which does use beans. Opt in by committing the enablement to this repo's `.claude/settings.json`.

This is the "solo project, commit it" case from the design: the entry is versioned so it applies on every machine and every clone, rather than being re-done per checkout in `settings.local.json`.

**Files:**
- Modify: `.claude/settings.json`

- [ ] **Step 1: Add the enablement entry**

`.claude/settings.json` currently holds only a `permissions.allow` list. Add `enabledPlugins` alongside it:

```json
{
  "permissions": {
    "allow": [
      "Bash(nixfmt:*)",
      "Bash(nix flake check:*)",
      "Bash(gh pr merge:*)"
    ]
  },
  "enabledPlugins": {
    "df-beans@skills-dir": true
  }
}
```

- [ ] **Step 2: Verify it is valid JSON**

Run: `jq . .claude/settings.json`

Expected: pretty-printed output, exit 0.

- [ ] **Step 3: Verify the switch takes effect**

This needs the plugin actually installed, so run `home-manager switch` (or the host's switch command) first, then from this repository:

```bash
claude plugin list
```

Expected: `df-beans@skills-dir` with `Status: ✔ loaded`, and `df-base@skills-dir` / `df-plannotator@skills-dir` also loaded via their own `defaultEnabled`.

Then check the negative case from any directory outside this repository:

```bash
cd /tmp && claude plugin list
```

Expected: `df-beans@skills-dir` reports `Status: ✘ disabled` there. That difference is the whole point of the epic.

- [ ] **Step 4: Confirm the beans hooks fire here and only here**

Start a session in this repository and confirm the beans priming instructions appear in context (the `SessionStart` hook output). Start one in an unrelated directory and confirm they do not.

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json
git commit -m "beans: enable the df-beans plugin for this repository

Bean: dotfiles-6l44"
```
