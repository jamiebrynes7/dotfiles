---
name: comment-cleanup
description: Analyze and clean up code comments for accuracy, completeness, and long-term maintainability. Use when the user asks to review or clean up comments, after generating documentation, or before finalizing a pull request with comment changes.
---

# Comment Cleanup

Analyze and fix code comments within changed code. Supports the current diff, the most recent commit, or all commits on the current branch. Every comment must earn its place by providing clear, lasting value. Inaccurate or outdated comments create technical debt that compounds over time.

## Scope

Only analyze comments that appear in changed code. Determine the scope from the user's request:

### Current diff (default)

Use when the user asks to clean up "current changes", "my diff", "uncommitted changes", or does not specify a scope.

```bash
git diff HEAD
```

This combines both staged and unstaged changes against HEAD. If the diff is empty, STOP and tell the user there are no changes to analyze.

### Most recent commit

Use when the user asks to clean up "last commit", "most recent commit", or "previous commit".

```bash
git diff HEAD~1..HEAD
```

### All commits on the current branch

Use when the user asks to clean up "branch changes", "all commits", "changes since main", or "PR changes".

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

Extract all comments (new, modified, or in modified hunks) from the diff output. These are the only comments in scope.

## Analysis

For each in-scope comment, evaluate against these criteria:

### 1. Factual Accuracy

Cross-reference every claim against the actual code:

- Function signatures match documented parameters and return types
- Described behavior aligns with actual code logic
- Referenced types, functions, and variables exist
- Edge cases mentioned are actually handled
- Performance or complexity claims are correct

### 2. Value Assessment

A comment must justify its existence. The only acceptable comments explain **why** the code does something, never **what** it does. Code is the single source of truth for "what" -- any comment that restates it is redundant at best and a future lie at worst.

**Remove unconditionally** any comment that:

- Restates or paraphrases what the code does (e.g. `// increment counter`, `// return the result`, `// loop through items`)
- Names the operation being performed (e.g. `// fetch user data` above a `fetchUserData()` call)
- Describes control flow that is already expressed by the code structure (e.g. `// check if null`, `// handle error case`)
- Translates code into English without adding context the code itself does not convey
- Exists only because "the function/block should have a comment"

There are **no exceptions** for "what" comments. If the code is too opaque to understand without a "what" comment, the code itself should be refactored (better names, extracted functions, clearer structure) -- not papered over with a comment.

**Also flag** comments that:

- Will become stale with likely code changes
- Reference temporary states or transitional implementations
- Contain TODOs or FIXMEs that have already been addressed

**Acceptable comments** explain:

- **Why** a non-obvious approach was chosen over the obvious one
- **Why** a workaround or hack exists (with links to issues/bugs when possible)
- **Why** a particular value, threshold, or constraint was picked
- Domain or business context that cannot be expressed in code

### 3. Completeness

Identify missing context where a comment would add value:

- Non-obvious side effects
- Critical assumptions or preconditions
- Complex algorithm rationale
- Business logic that isn't self-evident

### 4. Clarity

Flag comments that could mislead future maintainers:

- Ambiguous language with multiple interpretations
- Outdated references to refactored code
- Examples that don't match the current implementation

## Output

Present findings grouped by file, then apply fixes.

### Finding Format

```
**file:line** - [severity] description
  Suggestion: what to do
```

Severity levels:

| Level | Meaning |
|-------|---------|
| Remove | Comment adds no value or is misleading |
| Rewrite | Comment is inaccurate or unclear, needs rewriting |
| Add | Missing comment where one would provide value |

### Applying Fixes

After presenting findings, apply all suggested changes directly:

- **Remove**: Delete the comment
- **Rewrite**: Replace with an improved version
- **Add**: Insert the new comment

Do not ask for confirmation before applying. The user can review and revert via git if needed.
