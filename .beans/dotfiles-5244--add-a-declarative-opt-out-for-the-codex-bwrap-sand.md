---
# dotfiles-5244
title: Add a declarative opt-out for the codex bwrap sandbox check
status: todo
type: task
priority: low
created_at: 2026-09-04T10:09:56Z
updated_at: 2026-09-04T10:09:56Z
---

From the review of dotfiles-dist.

`DOTFILES_CODEX_SKIP_SANDBOX_CHECK` only silences the wrapper's check. It cannot be set for the activation-time warning in `home/programs/codex/default.nix` (`codexSandboxCheck`), so a host that knowingly runs Codex unsandboxed gets an unsuppressable warning on every `home-manager switch`. The only current escape is flipping `useLegacyLandlock`, which changes Codex's actual sandbox backend rather than just the warning — conflating a diagnostic with a behavioural switch.

## Todo

- [ ] Add a `checkSandbox` option (default `true`) separating "warn me about a broken bwrap sandbox" from "which backend Codex uses".
- [ ] Gate both `bwrapCheckFatal` and `bwrapCheckWarn` on it.
