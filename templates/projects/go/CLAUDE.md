# Go Project

Freshness: 2026-02-28

## Tech Stack

- Go
- just (task runner)
- golangci-lint (linting)
- Nix devShell (all tooling provided via direnv)

## Commands

- `just` — list all available targets
- `just build` — build all packages
- `just test` — run tests
- `just lint` — run golangci-lint
- `just fmt` — format code
- `just check` — run fmt, lint, test, and build (in that order)

## Project Structure

```
flake.nix    # Nix devShell with Go, golangci-lint, just, etc.
justfile     # Task definitions
.envrc       # Loads the devShell via direnv
```

## Conventions

- Run `just check` before committing — it formats, lints, tests, and builds.
- All tools (Go, linters, just) come from the Nix devShell via direnv. Nothing is installed globally.
