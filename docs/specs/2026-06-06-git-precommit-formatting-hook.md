# Spec: git pre-commit formatting hook (Nix + Rust)

Date: 2026-06-06
Rescopes bean: `dotfiles-b2sy` (was "Add Rust formatting hook for Claude Code")

## Goal

Enforce formatting mechanically at commit time via a version-controlled git
pre-commit hook, instead of a Claude Code agent (`PostToolUse`) hook. This makes
the check apply to *any* committer (human or agent, any editor) and gives agents
a tight "commit fails → read error → fix → re-commit" feedback loop. CI's
`nix flake check` remains the authoritative gate; this hook is the fast local
pre-flight.

Inspired by the "minimal setup" in
https://jonesrussell.github.io/blog/git-hooks-ai-agents/ — a committed
`.githooks/` directory selected via `core.hooksPath` — adapted to this repo's
Nix + direnv setup so wiring is zero-touch.

## Scope

In scope:

- Formatting checks only, for the two formatters already in the devShell:
  - `*.nix` → `nixfmt --check`
  - `*.rs` → `cargo fmt --check` (whole Rust workspace)
- A committed, executable `.githooks/pre-commit` script.
- Auto-wiring `core.hooksPath` via the repo's own devShell `shellHook`.
- Rescoping bean `dotfiles-b2sy` and a short `CLAUDE.md` note.

Out of scope (left to CI / future beans):

- `cargo clippy`, `nix flake check`, tests, or any non-formatting lint.
- A Nix git-hooks framework (e.g. cachix/git-hooks.nix). Hand-written script is
  sufficient and avoids a new flake input.
- Deploying anything globally via home-manager. This is repo-local only.

## Design

### Component 1: `.githooks/pre-commit`

A POSIX `sh` script, `chmod +x`, committed at the repo root.

Behavior:

The script runs with `set -e` so any non-zero command (including a formatter
reporting violations, or a missing formatter exiting "command not found")
aborts the script and blocks the commit.

1. Collect staged files:
   `git diff --cached --name-only --diff-filter=ACM`.
2. Detect whether the staged set contains any `*.nix` and/or any `*.rs` files.
   These flags are only triggers — they decide *whether* to run each formatter,
   not *what* it checks.
3. If any `*.nix` file is staged → run `nixfmt --check` on **all tracked `.nix`
   files** (`git ls-files '*.nix'`). Whole-repo, mirroring the Rust behavior.
4. If any `*.rs` file is staged → run `cargo fmt --all --check`. Whole-workspace,
   not just the staged files. The hook runs from the repo top-level, so cargo
   resolves the root workspace `Cargo.toml` by searching upward — no
   `--manifest-path` needed.
5. Any formatter that reports violations exits non-zero, which (via `set -e`)
   aborts the hook and blocks the commit. The hook prints the one-line fix
   command (`nixfmt $(git ls-files '*.nix')` / `cargo fmt --all`) to make
   recovery obvious.
6. If all applicable checks pass (or no `.nix`/`.rs` files are staged) → exit 0.

Decisions:

- **No eager tool-presence checks:** the hook does not probe `PATH` before
  running. If a formatter is missing it exits non-zero ("command not found") and
  `set -e` fails the commit — the same hard-fail outcome with less code.
- **Check-only:** the hook never modifies or re-stages files. It only reports
  and blocks. The committer fixes and re-commits.
- **Whole-repo, not staged-only:** both formatters check the entire repo/
  workspace (all tracked `.nix`; the whole Rust workspace) whenever their
  trigger fires. Simpler, consistent across both languages, and fine because the
  repo is expected to stay fully formatted. Consequence: the working-tree (not
  staged-blob) version of files is what's checked, so partially-staged hunks are
  checked as they appear on disk — accepted simplification for a personal repo.
- **Tool-absent = hard-fail (emergent):** committing from an environment without
  the formatters on `PATH` blocks the commit. The normal workflow is committing
  from inside the direnv-activated devShell, where both tools are present.

### Component 2: devShell wiring (auto `core.hooksPath`)

Add a `shellHook` that runs `git config core.hooksPath .githooks`.

Placement is critical: it MUST go in **this repo's own `devShells`** definition
(the `extraEnv` passed to `mkShells` at the bottom of `flake.nix`), NOT in the
shared `mkShells` / `baseShellPkgs` helper. `mkShells` is exported as
`lib.mkShells` and reused by downstream system repos; putting the hook there
would make it run in every downstream devShell. Keeping it in the repo-specific
`extraEnv` contains it to this repo.

Properties relied on:

- `git config` without `--global`/`--system` writes to `<repo>/.git/config` —
  local to this clone only, never affects other repos.
- `core.hooksPath = .githooks` is resolved relative to the repo top-level.
- The command is idempotent: re-running on every shell entry rewrites the same
  value, a no-op in effect.

Implementation sketch (final form decided during implementation):

```nix
devShells = mkShells {
  extraPackages = pkgs: [ pkgs.dotfiles.internal.rustToolchain ];
  extraEnv = pkgs: {
    RUST_SRC_PATH = "${pkgs.dotfiles.internal.rustToolchain}/lib/rustlib/src/rust/library";
    shellHook = ''
      git config core.hooksPath .githooks
    '';
  };
};
```

Note: `mkOne` merges `extraEnv pkgs` into the `mkShell` argument via `//`, so a
`shellHook` key is passed straight through to `pkgs.mkShell`.

### Component 3: bean rescope + docs

- Rewrite bean `dotfiles-b2sy`: new title
  ("git pre-commit formatting hook (Nix + Rust)"), updated context (git hook, not
  Claude Code agent hook), and a todo list matching this spec. Keep type
  `feature`.
- Add a short note to `CLAUDE.md` (Commands or Conventions section): the repo has
  a `.githooks/pre-commit` formatting gate, auto-wired by the devShell; commit
  from inside the devShell so the formatters are on `PATH`.

## Testing / acceptance

Manual verification:

1. After `direnv allow` / entering the devShell:
   `git config core.hooksPath` returns `.githooks`.
2. Stage a deliberately mis-formatted `.nix` file → `git commit` is blocked with
   a message naming the file and the fix command. Format it → commit succeeds.
3. Stage a deliberately mis-formatted `.rs` file → commit blocked. Run
   `cargo fmt` → commit succeeds.
4. Committing with no staged `.nix`/`.rs` files → hook is a no-op, commit passes.
5. (Tool-absent) From a shell without the devShell on `PATH`, staging a `.nix` or
   `.rs` file → commit hard-fails (formatter exits "command not found",
   `set -e` aborts the hook).
6. `.githooks/pre-commit` is tracked by git and executable; `.claude/settings.json`
   / gitignore do not exclude it.

## Risks / notes

- Hard-fail on missing tools means commits from a non-devShell environment that
  touch `.nix`/`.rs` are blocked. Acceptable given the direnv workflow; revisit
  if it becomes annoying.
- `cargo fmt --all --check` resolves the workspace manifest at the repo root
  (`./Cargo.toml`) by searching upward from the hook's cwd.
- Whole-workspace `cargo fmt --check` could flag a pre-existing unformatted file
  unrelated to the current commit. The repo is expected to stay fully formatted
  (CI enforces it), so this should be rare.
