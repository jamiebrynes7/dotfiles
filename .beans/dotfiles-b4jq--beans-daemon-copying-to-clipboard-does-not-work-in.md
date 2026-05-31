---
# dotfiles-b4jq
title: '[beans-daemon] copying to clipboard does not work in beans-serve iframe'
status: completed
type: bug
priority: normal
created_at: 2026-05-26T17:10:09Z
updated_at: 2026-05-31T14:57:04Z
---

Likely needs permissions as in https://stackoverflow.com/questions/61401384/can-text-within-an-iframe-be-copied-to-clipboard

## Summary of Changes

The launcher page (`crates/beansd/src/web/templates/index.html`) embeds the per-project `beans-serve` UI in an iframe. The parent page is served on the daemon's port and the iframe on the project's port, making them different origins. Browsers therefore block the Clipboard API inside the iframe unless the parent delegates it via Permissions Policy.

Added `allow="clipboard-write; clipboard-read"` to the iframe to delegate clipboard access to the framed origin. `clipboard-write` fixes the reported copy bug; `clipboard-read` is included to also support paste-from-clipboard inside the iframe.

Note: this delegates the modern `navigator.clipboard` API. The framed app must use that API (not legacy `document.execCommand('copy')`, which is unaffected by this attribute) for copy to work.
