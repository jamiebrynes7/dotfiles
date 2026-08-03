---
# dotfiles-0poj
title: '[beansd] Use "~" in the rendered paths where applicable'
status: completed
type: task
priority: normal
created_at: 2026-07-09T15:46:03Z
updated_at: 2026-08-02T13:40:15Z
---

This makes the paths shorter and easier to read at a glance

## Summary of Changes

Project paths rendered in the beansd launcher top bar (dropdown rows and the
active-project detail strip) now collapse $HOME to `~`. The full absolute path
remains available as a `title` tooltip on each path span.

- Added `tildify(path, home)` in `web/views.rs` — component-wise `strip_prefix`,
  so a sibling dir sharing a name prefix (`/home/jo-backup`) is not shortened,
  and only a leading $HOME collapses.
- `ProjectView` gained a derived `display_path`; `key` stays the verbatim
  absolute path and remains the lookup key in the `<option value>`, the
  `hx-get ?active=` poll, and the `hx-vals` heartbeat form.
- $HOME is resolved once at `Server::bind` and injected via `web::State` rather
  than read per request, and is canonicalized so it compares against registry
  keys (which `project_key::resolve` canonicalizes) — without that, a symlinked
  home directory would silently disable the shortening entirely.
- Errors, tracing fields and beansctl JSON stay absolute: those are
  machine-facing, and `ProjectSummary.key` is an RPC wire contract.
