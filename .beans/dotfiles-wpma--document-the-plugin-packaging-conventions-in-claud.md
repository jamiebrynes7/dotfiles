---
# dotfiles-wpma
title: Document the plugin packaging conventions in CLAUDE.md
status: todo
type: task
priority: normal
created_at: 2026-09-21T17:29:46Z
updated_at: 2026-09-21T17:30:08Z
parent: dotfiles-5nj7
---

**Files:**
- Modify: `CLAUDE.md` — the `### Packages` subsection under `## Conventions`, and the `Freshness:` line at the top

`CLAUDE.md` currently states that vendored upstream packages follow a fixed shape (`hashes.json` + `default.nix` + `update.sh`, with `update.sh` idempotent and run nightly by `auto-update.yml`). This change introduces two deliberate exceptions that a reader would otherwise treat as mistakes.

- [ ] **Step 1: Document plugin packages**

Add to the `### Packages` subsection:

```markdown
Paseo plugins are packaged one directory per plugin, named after the **plugin id** —
`packages/paseo-plugin-<id>/` — so `dotfiles.programs.paseo.plugins.<id>.package =
pkgs.dotfiles.paseo-plugin-<id>` needs no lookup table. An external plugin whose upstream
publishes no releases is pinned by commit SHA literally in its `default.nix`, with **no**
`hashes.json` and **no** `update.sh`: plugin code runs unsandboxed as the daemon user, so
every bump is a reviewed commit rather than a nightly auto-update PR. Omitting `update.sh`
is what keeps `auto-update.yml` away from it.
```

- [ ] **Step 2: Document the paseo patch**

Add to the same subsection, after the paseo IFD paragraph:

```markdown
`packages/paseo` is also the only package here that patches upstream source: a `postPatch`
makes the daemon's `savePersistedConfig` throw rather than overwrite a `config.json` that
is a symlink, because `home/programs/paseo.nix` always writes that file from the store and
the daemon's atomic save would otherwise rename a temp file over it. Both anchors use
`--replace-fail`, and `postInstall` greps `$out` for the sentinel, so an upstream rewrite
fails the build instead of silently shipping an unguarded daemon.
```

- [ ] **Step 3: Update the freshness date**

Change the `Freshness:` line at the top of `CLAUDE.md` to `2026-09-21`.

- [ ] **Step 4: Verify**

Run: `git diff CLAUDE.md`

Expected: the two new paragraphs plus the date. Re-read the surrounding text to confirm the new paragraphs don't contradict the existing "every directory under `packages/` is auto-discovered" or "update.sh must fail on anything it cannot resolve" statements — they are exceptions to the *shape*, not to those rules.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: document paseo plugin packaging conventions" -m "Bean: dotfiles-wpma"
```
