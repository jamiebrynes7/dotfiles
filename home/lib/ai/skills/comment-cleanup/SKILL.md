---
name: comment-cleanup
description: Analyze and clean up code comments for accuracy, completeness, and long-term maintainability. Use when the user asks to review or clean up comments, after generating documentation, or before finalizing a pull request with comment changes.
---

# Comment Cleanup

Analyze and fix code comments within changed code. Supports the current diff, the most recent commit, or all commits on the current branch. Inaccurate or outdated comments create technical debt that compounds over time.

## Scope

Only analyze comments that appear in changed code.

**REQUIRED**: Load the 'diff-scope' skill to determine which git diff to analyze based on the user's request.

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

**REQUIRED**: Load the 'house-style-code-comments' skill. It defines which comments earn their place, which are removed unconditionally, and which are worth keeping.

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

## Delegating the judgment pass

Dispatch a subagent to decide what to cut, then verify its work. The criteria in this section are what you hand it rather than a pass you run first.

An author cannot review their own comments: having written the code, every comment feels load-bearing because the bug behind it is still fresh. A reviewer with no stake in the change carries no such attachment.

Give the subagent the in-scope files, the framing that it is a principal engineer whose default answer to "should this comment exist?" is no, and the criteria: tell it to load 'house-style-code-comments' for the value judgment, and pass the accuracy, completeness, and clarity criteria above inline. Do not have it load `comment-cleanup` -- it would dispatch a subagent of its own. Have it apply its removals and rewrites directly, and return them in the finding format below with line numbers as they stood before its edits.

Verify before reporting:

1. No non-comment lines changed -- read `git diff -U0` and confirm every removed or added line is comment-only.
2. Every surviving factual claim is true. A fresh-context reviewer cuts well but asserts badly, so check each claim against the code and its actual runtime behaviour.

Its pass is subtractive, so **Add** findings and any claim it got wrong remain yours to apply.

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

The subagent's removals and rewrites are already on disk. Apply the remainder directly:

- **Remove**: Delete the comment
- **Rewrite**: Replace with an improved version
- **Add**: Insert the new comment

Do not ask for confirmation before applying. The user can review and revert via git if needed.
