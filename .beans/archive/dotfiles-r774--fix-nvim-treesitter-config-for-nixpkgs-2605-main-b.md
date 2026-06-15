---
# dotfiles-r774
title: Fix nvim-treesitter config for nixpkgs 26.05 main-branch rewrite
status: completed
type: bug
priority: normal
created_at: 2026-06-09T09:59:11Z
updated_at: 2026-06-09T10:07:59Z
---

After updating to nixpkgs 26.05, nvim fails at startup: module 'nvim-treesitter.configs' not found.

nixpkgs 26.05 ships the upstream nvim-treesitter `main` branch rewrite (0.10.0-unstable-2026-04-03), which removed the `nvim-treesitter.configs` module and the `.setup{ highlight = ... }` module system. Highlighting is now Neovim-native via `vim.treesitter.start()`.

Grammars are already provided via `nvim-treesitter.withAllGrammars` in default.nix, so no install management is needed — just enable highlighting per buffer.

## Tasks
- [ ] Rewrite home/programs/nvim/config/lua/plugins/treesitter.lua to use vim.treesitter.start() via a FileType autocmd
- [x] Validate (loaded edited file in headless nvim — clean)

## Summary of Changes

Replaced the removed `require('nvim-treesitter.configs').setup{ highlight = { enable = true } }` call with a FileType autocmd that calls Neovim's built-in `vim.treesitter.start(buf)` (guarded by pcall for filetypes lacking a parser).

nixpkgs 26.05 ships nvim-treesitter's `main`-branch rewrite (0.10.0-unstable), which deleted the `nvim-treesitter.configs` module and the whole `.setup{}` module system. Grammars are still supplied by `nvim-treesitter.withAllGrammars` in default.nix, so no install management was needed.

Verified by loading the edited file directly in `nvim --headless --clean` (exit 0). `nix flake check` was run but fails on an unrelated beans-frontend pnpm build crash on darwin; it does not parse this Lua file regardless (it is copied verbatim via xdg.configFile).
