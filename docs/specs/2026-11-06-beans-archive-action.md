Date: 2026-11-06

# Extract beans archiving into a shared GitHub Action

## Goal

`.github/workflows/archive-beans.yml` moves completed and scrapped beans into `.beans/archive/` every
week, but only `dotfiles` has it. Other repos use beans too, and copying the workflow would mean
maintaining several copies of the same logic.

Move the logic into a new public repo, `jamiebrynes7/beans-archive-action`, as a composite action.
`dotfiles` and `nimbus` adopt it now. `sys-enterprise` can adopt it later; it is out of scope here.

## Architecture

There are three units:

- **`beans-archive-action`**: a new public repo holding one composite action. It must be public
  because `dotfiles` is public and cannot use an action from a private repo.
- **Caller workflows** in `dotfiles` and `nimbus`: each owns its cron, its permissions and its token.
- **The `dotfiles` flake**: supplies the beans CLI, at a commit pinned in the action, through
  `nix run github:jamiebrynes7/dotfiles/<full-commit-sha>#beans`.

The composite action is preferred over a reusable workflow so that each repo keeps ownership of its
own job and can add steps around the action.

## Action interface

| Input          | Required | Default  | Meaning                                                              |
| -------------- | -------- | -------- | -------------------------------------------------------------------- |
| `token`        | yes      | none     | Token used for checkout, the PR and the merge. See "Authentication". |
| `auto-merge`   | no       | `true`   | Enable auto-merge on the PR. When `false`, leave the PR open.        |
| `merge-method` | no       | `rebase` | One of `merge`, `squash` or `rebase`. Used only when auto-merging.   |

These stay fixed, with no input: the `.beans` path (all current beans repos use it), the branch name,
the commit message and PR text, and the beans flake reference.

A caller looks like this:

```yaml
on:
  schedule:
    - cron: "0 5 * * 1"
  workflow_dispatch:

permissions:
  contents: read

jobs:
  archive-beans:
    runs-on: ubuntu-latest
    steps:
      - id: app-token
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.POPPET_BOT_CLIENT_ID }}
          private-key: ${{ secrets.POPPET_BOT_PRIVATE_KEY }}
      - uses: jamiebrynes7/beans-archive-action@<full-commit-sha>
        with:
          token: ${{ steps.app-token.outputs.token }}
```

## Behaviour

The action runs these steps in order:

1. Check out the default branch using `token`, without persisting credentials. It is always the
   default branch because a manual run from another branch would otherwise force-push that branch's
   commits onto `beans/archive`, and so into any open archive PR with auto-merge enabled.
2. Install Nix.
3. Run `nix run github:jamiebrynes7/dotfiles/<full-commit-sha>#beans -- archive`.
4. Open or update a PR from the fixed branch `beans/archive` with `peter-evans/create-pull-request`,
   staging only `.beans`. Keep the existing commit message and title,
   `beans: archive completed beans`.
5. If `auto-merge` is `true` and an open PR exists, run `gh pr merge --auto` with `merge-method`.

Three things change from today's workflow:

- **The branch is fixed, not timestamped.** A PR stuck on a failing required check gets updated the
  next week, rather than a new PR being added alongside it. Both callers have required checks, so
  this can happen.
- **The "check for changes" step is removed.** `create-pull-request` already opens no PR when there
  is no diff, and it includes the untracked files that `beans archive` creates.
- **Merge behaviour is configurable.** See the inputs above.

## Beans version

The action builds beans from the `dotfiles` flake at a fixed commit, so the beans it runs changes only
when that pin is bumped. Upstream's latest release, v0.4.2, is not an option: the dotfiles pin is 388
commits ahead of it and has diverged by 2 commits. The cost is a source build of about 3 minutes per
run, which is acceptable for a weekly job.

CI can lag the beans the machines run until the pin is bumped. That is accepted in exchange for
nothing moving without a reviewed commit, and a bump is only needed when a beans change affects
archiving.

## Versioning and pinning

Callers pin the action by full commit SHA. The action receives a write token, and this matches how
paseo plugins are pinned here. Changing the action therefore needs a reviewed bump commit in each
caller. The repo needs no `v1` tag.

Third-party actions inside the composite are also pinned by full SHA, since a SHA-pinned caller would
otherwise still pick up whatever their tags later point to.

The `dotfiles` flake reference is pinned by full SHA too, so a caller's SHA pin fixes both the
action's logic and the beans build it runs. Moving to a newer beans takes two reviewed commits: one
bumping the flake SHA in the action, then one bumping the action SHA in each caller. No automation
bumps either pin.

## Authentication

`token` must not be `GITHUB_TOKEN`, because PRs opened with it do not trigger workflows. On `nimbus`
the required checks would never report and the PR would never merge, so the action fails if given
it. The input accepts any other token with write access to contents and pull requests, so the action
is not tied to GitHub Apps and never handles a private key. All writes go through `token`, so callers
only grant the job `contents: read`.

Both callers use the existing poppet bot app. `nimbus` has neither of its credentials yet, so before
adopting the action the user must:

- install the app on `nimbus`, if it is not already installed
- add `POPPET_BOT_CLIENT_ID` to `nimbus` as a variable
- add `POPPET_BOT_PRIVATE_KEY` to `nimbus` as a secret

## Repo compatibility

| Repo       | Default branch | Rebase allowed | Auto-merge | Required checks | Approvals needed |
| ---------- | -------------- | -------------- | ---------- | --------------- | ---------------- |
| `dotfiles` | `master`       | yes            | on         | `flake-check`   | none             |
| `nimbus`   | `main`         | yes (only)     | on         | `ci`, `infra`   | 0                |

`flake-check` passes on the existing bot-authored archive PRs in `dotfiles` (#415). `ci` and `infra`
both reported on an earlier beans-only `nimbus` PR (#160). An archive PR in either repo should
therefore not hang waiting on a check that never runs. The `nimbus` ruleset also sets
`require_extra_approval_for_unattributed_changes`, whose effect on a bot-authored PR is unverified.
The first `nimbus` run settles that.

## Error handling

Each failure leaves a red job and no silent loss. Archived files only ever reach the default branch
through a PR.

- **Nix install, build or `beans archive` fails:** the job fails before any PR is opened. The fixed
  flake SHA means a later break on `dotfiles` master cannot cause this.
- **`create-pull-request` fails, for example on a bad token:** the job fails with no PR.
- **`gh pr merge` fails, for example because the repo has auto-merge off or disallows the merge
  method:** the job fails and the PR stays open. The caller sets `auto-merge: false` or changes
  `merge-method`.
- **Required checks fail on the PR:** auto-merge waits, the PR stays open, and the next run updates
  it.

## Migration

1. Create the repo with the action, a README covering the inputs and token requirement, and an
   open-source license.
2. Replace the steps in `dotfiles`' `archive-beans.yml` with the action, keeping its cron.
3. Complete the `nimbus` credential setup and add the same caller there.

## Testing

The action repo has no CI of its own. The behaviour is verified with `workflow_dispatch` runs of the
real callers after each is merged:

- **`dotfiles`:** a run with beans to archive opens and merges a PR. A second run with nothing left to
  archive opens no PR and passes.
- **`nimbus`:** a run opens a PR, its `ci` and `infra` checks report, and it rebase-merges without
  manual action.
