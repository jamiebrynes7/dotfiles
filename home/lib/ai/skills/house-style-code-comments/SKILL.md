---
name: house-style-code-comments
description: Use when writing, reviewing, or cleaning up code comments. Defines which comments earn their place - why-not-what, the categories that always get removed, and the few kinds worth keeping.
cc:user-invocable: false
---

# House Style: Code Comments

Every comment must earn its place. Code is the single source of truth for *what* it does, so a comment restating it is redundant on the day it lands and a lie the first time the code changes without it.

The only comments worth keeping explain **why**.

## Default to removal

Keep a comment only when you can name the specific wrong action a reader would take without it — a change they would make that silently breaks something. "It adds useful context" is not an answer.

## Always remove

- Restates or paraphrases what the code does — `// increment counter`, `// return the result`, `// loop through items`
- Names the operation being performed — `// fetch user data` above a `fetchUserData()` call
- Describes control flow the code structure already expresses — `// check if null`, `// handle error case`
- Translates code into English without adding anything the code does not convey
- Exists because the function or block "should have a comment"
- Argues with an approach that is not in the code — `// rather than X`, `// the obvious way would be Y, but`. These pass the why-not-what test but answer a question the reader never asked, and they age badly as the alternative loses relevance. The line is whether a concrete failure mode is named: "the obvious `map` here deadlocks under concurrent writes" is worth keeping; "rather than a map" on its own is not.
- Narrates the change that introduced it — `// as discussed`, `// new approach`, `// per the plan`. Temporally coupled to a moment the reader was not present for and cannot recover.
- Describes what the code **used to do** — `// previously returned null`, `// no longer uses the cache`. Comments describe what *is*; historical narration contradicts the code the instant it is read.

There are no exceptions for "what" comments. If code is too opaque to follow without one, fix the code — better names, extracted functions, clearer structure — rather than papering over it.

Bug-fix archaeology — the sequence of attempts behind the current code — belongs in the commit message, which is where someone will go looking for it.

## Worth keeping

- **Why** a non-obvious approach was necessary, when the obvious one has a concrete failure mode worth naming
- **Why** a workaround exists, linking the issue when possible
- **Why** a particular value, threshold, or constraint was chosen
- A load-bearing subtlety whose removal would silently break something
- Domain or business context the code cannot express

## Also flag

- Comments likely to churn when the code structure changes
- References to temporary states or transitional implementations
- TODOs and FIXMEs that have already been addressed
