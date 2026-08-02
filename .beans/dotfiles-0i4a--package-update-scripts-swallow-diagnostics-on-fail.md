---
# dotfiles-0i4a
title: Package update scripts swallow diagnostics on failure
status: todo
type: task
priority: low
created_at: 2026-08-02T14:01:38Z
updated_at: 2026-08-02T14:01:38Z
parent: dotfiles-fo1w
---

Every `packages/*/update.sh` has an error branch that is unreachable under `set -euo pipefail`:

```bash
hash=$(nix store prefetch-file --json "$url" 2>/dev/null | jq -r ".hash")
if [[ -z "$hash" || "$hash" == "null" ]]; then
  echo "Error: Failed to fetch hash for ${nix_platform}" >&2
  exit 1
fi
```

The pipeline failing aborts the script before the check runs, and `2>/dev/null` has already discarded the real message from curl/nix. In the nightly `auto-update` workflow this surfaces as a bare non-zero exit with no diagnostics.

Affects `beans`, `claude-code`, `codex`, `cship`, `plannotator`, `sprite` — fix consistently across all six.

## Todo

- [ ] Replace the dead branches with `if ! out=$(...); then ...; fi` and stop discarding stderr
- [ ] Consider a `curl -sfI` HEAD check on one artifact in `packages/claude-code/update.sh` — the GCS manifest can be published before the binaries finish uploading, producing a green update PR whose `nix flake check` fails

Raised in review of dotfiles-j5ab.
