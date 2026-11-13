---
# dotfiles-2vhr
title: 'agent-status: show typed links on the status card'
status: completed
type: feature
priority: normal
created_at: 2026-11-13T09:23:02Z
updated_at: 2026-11-13T09:46:22Z
---

Add an optional links input to set_status (up to 3 { kind: pr | review | other, url }) and render each as a link on the status card. Replaces per call, like waiting_on. Stored rows keep kind as a plain string so older clients render new kinds as other.

- [x] pr_url in the tool input, row, and store schemas
- [x] Tool description tells agents to pass it
- [x] Card renders it as an ExternalLink
- [x] Tests + typecheck

## Summary of Changes

- set_status takes an optional links list (1-3 of { kind: pr | review | other, url }), http(s) only, replaced on every call like waiting_on. The tool description and the Stop hook reminder both ask agents to keep passing links that still apply.
- Saved statuses and timeline rows carry links with kind as a plain string, so a client older than a new kind renders it as other; the row version stays 1.
- The card shows each link on its own line in muted, underlined text: a GitHub PR as owner/repo#N, a review as "Review", anything else as the URL without scheme or query.
- demo/seed.sh starts four Haiku agents covering every link kind; ts/paseo-demo.sh now turns on daemon.mcp.injectIntoAgents, without which no plugin agent tool reached demo agents.
