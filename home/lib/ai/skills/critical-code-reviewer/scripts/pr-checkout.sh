#!/usr/bin/env bash
set -euo pipefail

# Checks out a GitHub PR into a temporary directory for local code review.
# Uses git worktree for same-repo PRs, shallow clone for cross-repo PRs.

usage() {
    cat <<EOF
Usage:
  $(basename "$0") setup <PR_NUMBER> [--repo owner/repo]
  $(basename "$0") cleanup <DIR>
EOF
    exit 1
}

# Get the owner/repo slug for the current repo's remote.
current_repo_slug() {
    gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null
}

cmd_setup() {
    local pr_number=""
    local target_repo=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo)
                target_repo="$2"
                shift 2
                ;;
            *)
                if [[ -z "$pr_number" ]]; then
                    pr_number="$1"
                    shift
                else
                    usage
                fi
                ;;
        esac
    done

    [[ -z "$pr_number" ]] && usage

    # Clean stale worktrees from prior runs.
    git worktree prune 2>/dev/null || true

    if [[ -n "$target_repo" ]]; then
        local current_slug
        current_slug=$(current_repo_slug)

        if [[ "$current_slug" != "$target_repo" ]]; then
            echo "Error: Cross-repo reviews are not supported. Please cd into the target repo first." >&2
            exit 1
        fi
    fi

    setup_worktree "$pr_number" ""
}

# Same-repo checkout via git worktree + gh pr checkout.
setup_worktree() {
    local pr_number="$1"
    local repo_flag="$2"
    local tmpdir
    tmpdir=$(mktemp -d)

    # Create a detached worktree so we don't collide with existing branches.
    git worktree add --detach "$tmpdir" HEAD >/dev/null 2>&1

    # Checkout the PR branch within the worktree.
    if [[ -n "$repo_flag" ]]; then
        (cd "$tmpdir" && gh pr checkout "$pr_number" --repo "$repo_flag" --detach) >/dev/null 2>&1
    else
        (cd "$tmpdir" && gh pr checkout "$pr_number" --detach) >/dev/null 2>&1
    fi

    echo "$tmpdir"
}

cmd_cleanup() {
    local dir="$1"

    [[ -z "$dir" ]] && usage
    [[ ! -d "$dir" ]] && return 0

    # Check if this directory is a git worktree of the current repo.
    if git worktree list --porcelain 2>/dev/null | grep -q "^worktree ${dir}$"; then
        git worktree remove --force "$dir" 2>/dev/null
    else
        rm -rf "$dir"
    fi
}

# --- Main ---

[[ $# -lt 1 ]] && usage

subcommand="$1"
shift

case "$subcommand" in
    setup)   cmd_setup "$@" ;;
    cleanup) cmd_cleanup "$@" ;;
    *)       usage ;;
esac
