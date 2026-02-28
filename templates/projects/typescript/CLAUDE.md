# TypeScript Project

Freshness: 2026-02-28

## Tech Stack

- TypeScript
- Node.js
- npm
- Nix devShell (tooling provided via direnv)

## Commands

- `npm run build` — build the project
- `npm test` — run tests
- `npm run lint` — run linter
- `npm run fmt` — format code

## Project Structure

```
flake.nix       # Nix devShell with Node.js
package.json    # Dependencies and npm scripts
.envrc          # Loads the devShell via direnv
```

## Conventions

- Lint and format before committing. Define project tasks as npm scripts in `package.json`.
- Node.js comes from the Nix devShell via direnv. Nothing is installed globally.
