---
# dotfiles-6epm
title: '[beansd] Use custom select element for project selector'
status: completed
type: task
priority: normal
created_at: 2026-06-10T07:17:19Z
updated_at: 2026-07-04T21:15:25Z
---

This will provide a more native experience - https://developer.mozilla.org/en-US/docs/Learn_web_development/Extensions/Forms/Customizable_select

## Summary of Changes

Replaced the `<details>`/`<summary>` disclosure-hack project switcher with the
customizable native `<select>` element (`appearance: base-select`) in
`top_bar.html`, restyled in `app.css`:

- The `<button>` + `<selectedcontent>` mirrors the active project's name (path
  and badge hidden in the button, shown in the picker rows).
- A disabled/hidden placeholder `<option>` is always rendered as the button-label
  fallback; the active project's option carries `selected` and wins by document
  order, so unknown/absent keys fall back cleanly to "Select a project".
- Selection navigates via an `onchange` handler that URL-encodes the project key
  (more robust than the old raw-path anchors).
- Suppressed the UA's default `::picker-icon` in favour of the existing caret,
  and kept the placeholder out of the picker via `option[hidden]`.

Added a render assertion in `partial_lists_registered_projects` pinning the
placeholder + selected-option contract.
