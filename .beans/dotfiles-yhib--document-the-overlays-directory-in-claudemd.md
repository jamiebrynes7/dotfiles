---
# dotfiles-yhib
title: Document the overlays/ directory in CLAUDE.md
status: todo
type: task
priority: normal
created_at: 2026-08-19T10:58:19Z
updated_at: 2026-08-19T10:58:25Z
parent: dotfiles-yk15
blocked_by:
    - dotfiles-rdkr
---

**Files:**
- Modify: `CLAUDE.md` — the freshness date, the Project Structure tree, the Packages convention section

`overlays/` is a new top-level directory, and it introduces a second route by which something lands under `pkgs.dotfiles.*` — an overlay fragment wrapping an upstream flake input, rather than an auto-discovered `packages/` directory. Both routes end at the same namespace, and the existing convention text only describes the first.

- [ ] **Step 1: Bump the freshness date**

Change the line near the top of `CLAUDE.md`:

```
Freshness: 2026-08-19
```

- [ ] **Step 2: Add `overlays/` to the Project Structure tree**

In the fenced tree block, after the `modules/` line, add:

```
overlays/            # Overlay fragments wrapping upstream flake inputs (paseo)
```

- [ ] **Step 3: Extend the Packages convention section**

In the `### Packages` section, after the paragraph ending "Reference them as `pkgs.dotfiles.claude-code`, not `pkgs.claude-code`.", add:

```markdown
Upstream software we consume as a flake input rather than build from a `packages/`
directory lands in the same namespace, via an overlay fragment under `overlays/`
that extends the set rather than clobbering it — `dotfiles = (prev.dotfiles or { })
// { ... }`, the same shape `crates/default.nix` uses. Such an overlay must be
listed in `defaultOverlays` **after** `dotfilesOverlay`, which plain-assigns
`dotfiles`. `pkgs.dotfiles.paseo` is the current example; it carries two patches
upstream has not landed, so expect its `npmDepsHash` to need re-pointing at every
version bump.
```

- [ ] **Step 4: Verify the claims are still true**

Run: `grep -n "overlays/paseo.nix" flake.nix`
Expected: one line, inside `defaultOverlays`, positioned after the `dotfilesOverlay` entry.

Run: `nix eval --raw .#packages.aarch64-darwin.paseo.name`
Expected: `paseo-0.3.1`

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "CLAUDE.md: document the overlays/ directory

Bean: dotfiles-yhib"
```
