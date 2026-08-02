---
# dotfiles-6f5q
title: Home-manager eval check harness
status: todo
type: feature
created_at: 2026-08-02T12:10:36Z
updated_at: 2026-08-02T12:10:36Z
parent: dotfiles-zo7y
---

Adds the first evaluation coverage for `home/`. Today `nix flake check` builds packages, Rust and nixfmt but never evaluates a home-manager configuration, so a broken module or a failing assertion in `home/` reaches CI undetected — and every task in this epic would otherwise be unverifiable.

**Owns:** `checks/home-eval.nix` (a minimal home-manager module enabling the AI-assistant programs) and the `home-eval` check wired into `flake.nix`'s `checks` attribute.
