---
name: comment-cleanup
description: Analyze and clean up code comments for accuracy, completeness, and long-term maintainability. Use when the user asks to review or clean up comments, after generating documentation, or before finalizing a pull request with comment changes.
---

# Comment Cleanup

Analyze and fix code comments within changed code. Supports the current diff, the most recent commit, or all commits on the current branch. Every comment must earn its place by providing clear, lasting value. Inaccurate or outdated comments create technical debt that compounds over time.

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

A comment must justify its existence. The only acceptable comments explain **why** the code does something, never **what** it does. Code is the single source of truth for "what" -- any comment that restates it is redundant at best and a future lie at worst.

Default to removal. Keep a comment only when you can name the specific wrong action a reader would take without it -- a change they would make that silently breaks something. "It adds useful context" is not an answer.

**Remove unconditionally** any comment that:

- Restates or paraphrases what the code does (e.g. `// increment counter`, `// return the result`, `// loop through items`)
- Names the operation being performed (e.g. `// fetch user data` above a `fetchUserData()` call)
- Describes control flow that is already expressed by the code structure (e.g. `// check if null`, `// handle error case`)
- Translates code into English without adding context the code itself does not convey
- Exists only because "the function/block should have a comment"
- Argues with an approach that is not in the code (`// rather than X`, `// the obvious way would be Y, but`). These pass the why-not-what test yet answer a question the reader never asked, and they age badly as the alternative loses relevance. Bug-fix archaeology belongs in the commit message.

There are **no exceptions** for "what" comments. If the code is too opaque to understand without a "what" comment, the code itself should be refactored (better names, extracted functions, clearer structure) -- not papered over with a comment.

**Also flag** comments that:

- Will become stale with likely code changes
- Reference temporary states or transitional implementations
- Contain TODOs or FIXMEs that have already been addressed

**Acceptable comments** explain:

- **Why** a workaround exists, linking the issue or bug when possible
- **Why** a particular value, threshold, or constraint was picked
- A load-bearing subtlety whose removal would silently break something
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

## Delegating the judgment pass

Dispatch a subagent to decide what to cut, then verify its work. The criteria above are what you hand it rather than a pass you run first.

An author cannot review their own comments: having written the code, every comment feels load-bearing because the bug behind it is still fresh. A reviewer with no stake in the change carries no such attachment.

Give the subagent the in-scope files, the criteria above (inline -- it should not load this skill and dispatch again), and the framing that it is a principal engineer whose default answer to "should this comment exist?" is no. Have it apply its removals and rewrites directly, and return them in the finding format below with line numbers as they stood before its edits.

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
