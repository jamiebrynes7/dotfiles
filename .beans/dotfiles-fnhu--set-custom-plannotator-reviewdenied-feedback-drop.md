---
# dotfiles-fnhu
title: Set custom plannotator review.denied feedback (drop independent-review point)
status: completed
type: task
priority: normal
created_at: 2026-07-21T13:13:18Z
updated_at: 2026-07-21T13:18:46Z
---

**Goal:** Declaratively set plannotator's code-review `review.denied` output via the `home/programs/plannotator` nix module so it keeps the triage instruction and the describe-concretely paragraph but drops the "independently review the diff yourself" instruction (point 2 of the built-in default).

**Approach:** Render `~/.plannotator/config.json` from a nix attrset (mirroring the `home/programs/cursor` `mcp.json` / `home/programs/claude-code` `settings.json` idiom: `pkgs.writeText "…json" (builtins.toJSON {…})` wired via `home.file`). The rendered config must preserve the existing `diffOptions.defaultDiffType = "uncommitted"` and add `prompts.review.denied`.

**Files:**
- Modify: `home/programs/plannotator/default.nix`

**Caveat (one-time, out of band):** `~/.plannotator/config.json` currently exists as an *unmanaged* real file and no `backupFileExtension` is set in this repo, so the first `home-manager`/`darwin-rebuild` switch will fail on a file conflict. Remove or back up that file before switching:
`mv ~/.plannotator/config.json ~/.plannotator/config.json.bak` (or `rm`).

---

- [x] **Step 1: Add config rendering to the `let` block**

In `home/programs/plannotator/default.nix`, inside the existing `let … in` (after the `plannotatorHook` binding, before `in`), add the prompt string and JSON file:

\`\`\`nix
  # Code-review "denied" feedback: keep triage + concreteness, drop the
  # "independently review the diff yourself" instruction from the default.
  reviewDeniedPrompt = ''
    The findings above came from an automated review of the current changes.

    Triage each incoming finding — open the code it points at and give a verdict (Confirmed / Partly / Not a bug / Intended) with evidence (file:line + what the code actually does). Say whether it's introduced by these changes, pre-existing, or a deliberate scope decision. Rank by real user impact.

    For each confirmed issue, describe it concretely: the exact place it lives and the real-world trigger that hits it — the specific call, endpoint, command, input, or user action — plus the conditions under which it goes wrong. Not an abstract description.'';

  configJson = pkgs.writeText "plannotator-config.json" (
    builtins.toJSON {
      diffOptions.defaultDiffType = "uncommitted";
      prompts.review.denied = reviewDeniedPrompt;
    }
  );
\`\`\`

- [x] **Step 2: Wire the config file into `home.file`**

In the `config = lib.mkMerge [ … ]`, extend the shared block that is guarded by `lib.mkIf (cfg.claude-code.enable || cfg.codex.enable)` (the one that currently sets `home.packages = [ plannotatorWrapper ];`) so it also writes the config. The config is assistant-agnostic, so it belongs in this shared block, not the per-assistant ones:

\`\`\`nix
    (lib.mkIf (cfg.claude-code.enable || cfg.codex.enable) {
      home.packages = [ plannotatorWrapper ];
      home.file.".plannotator/config.json".source = configJson;
    })
\`\`\`

- [x] **Step 3: Format**

Run: \`nixfmt home/programs/plannotator/default.nix\`
Expected: no diff / exits clean (the pre-commit hook runs `nixfmt --check`).

- [x] **Step 4: Validate the flake**

Run: \`nix flake check\`
Expected: PASS (includes the `nixfmt` format check and the Rust build; the plannotator module must still evaluate).

- [x] **Step 5: Verify the rendered JSON contents**

After a `home-manager`/`darwin-rebuild` switch (having removed the old unmanaged file per the caveat), inspect the deployed file:
Run: \`cat ~/.plannotator/config.json\`
Expected: valid JSON with \`"diffOptions":{"defaultDiffType":"uncommitted"}\` and \`"prompts":{"review":{"denied":"The findings above came from an automated review…"}}\`, and the denied text contains NO "Independently review the current diff yourself" sentence.

- [x] **Step 6: Commit**

\`\`\`bash
git add home/programs/plannotator/default.nix .beans/
git commit -m "home/programs/plannotator: set custom review.denied feedback

Render ~/.plannotator/config.json declaratively with a custom
prompts.review.denied that drops the independent-review instruction.

Bean: dotfiles-fnhu"
\`\`\`

## Summary of Changes

Extended `home/programs/plannotator/default.nix` to render `~/.plannotator/config.json` declaratively (via `pkgs.writeText` + `builtins.toJSON`, wired through `home.file`, matching the cursor/claude-code module idiom). The rendered config preserves `diffOptions.defaultDiffType = "uncommitted"` and adds a custom `prompts.review.denied`:

- Keeps the triage instruction and the describe-concretely paragraph.
- Drops the "independently review the diff yourself" instruction (point 2 of the built-in default).
- Opening sentence reworded from "came from an automated review" to "are reviewer comments on the current changes" (per user review — the annotations are human-authored).

Verified via `nix flake check` (passes, incl. nixfmt gate) and by evaluating the rendered JSON with `nix eval`.

Note: `~/.plannotator/config.json` was an unmanaged real file; it must be removed/backed up before the first switch (no `backupFileExtension` set).
