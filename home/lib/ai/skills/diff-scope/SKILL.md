---
name: diff-scope
description: Determine which git diff to analyze based on the user's request. Supports current diff, most recent commit, or current branch.
cc:user-invocable: false
cc:allowed-tools: Bash(git diff:*), Bash(git merge-base:*), Bash(git rev-parse:*)
---

# Diff Scope

Determine which git diff to analyze based on the user's request.

## Current diff (default)

Use when the user mentions "current changes", "my diff", "uncommitted changes", or does not specify a scope.

```bash
git diff HEAD
```

This combines both staged and unstaged changes against HEAD.

## Most recent commit

Use when the user mentions "last commit", "most recent commit", or "previous commit".

```bash
git diff HEAD~1..HEAD
```

## All commits on the current branch

Use when the user mentions "branch changes", "all commits", "changes since main", or "this branch".

First, detect the default branch:

```bash
git rev-parse --verify main 2>/dev/null && echo main || echo master
```

Then diff against it using the merge-base:

```bash
git diff $(git merge-base <default-branch> HEAD)..HEAD
```

---

If the selected diff is empty, STOP and tell the user there are no changes to analyze.
