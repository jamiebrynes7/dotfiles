---
name: writing-plans
description: "Use when you have a spec or requirements for a multi-step task, before touching code. Decomposes the spec into bite-sized TDD tasks; emits a beans hierarchy (epic / feature / task) when the beans CLI is available, otherwise a markdown plan."
---

# Writing Plans

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for our codebase and questionable taste. Document everything they need to know: which files to touch for each task, the actual code, tests, docs they might need to check, how to verify it. Bite-sized tasks. DRY. YAGNI. TDD. Frequent commits.

Assume they are a skilled developer, but know almost nothing about our toolset or problem domain. Assume they don't know good test design very well.

**Announce at start:** "I'm using the writing-plans skill to create the implementation plan."

**Inputs:** a spec (typically at `docs/specs/YYYY-MM-DD-<topic>.md`) plus any constraints raised during brainstorming.

## Output Mode

The first action in this skill is to detect the output mode:

```bash
if command -v beans >/dev/null 2>&1; then mode=beans; else mode=markdown; fi
```

- **beans mode** — produce an epic → feature → task hierarchy in beans. The bean bodies hold the bite-sized TDD step lists. This is the default whenever beans is available.
- **markdown mode** — write a single markdown plan file at `docs/specs/plans/YYYY-MM-DD-<feature>.md`. Used only when beans is not on `$PATH`.

The Scope Check, File Structure, Bite-Sized Task Granularity, No Placeholders, and Self-Review sections below apply to both modes — only the final emission differs.

## Scope Check

If the spec covers multiple independent subsystems, it should have been broken into sub-project specs during brainstorming. If it wasn't, suggest breaking this into separate plans — one per subsystem. Each plan should produce working, testable software on its own.

In beans mode, multiple subsystems become multiple epics, not one epic with too many features.

## File Structure

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and your edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure — but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Bite-Sized Task Granularity

Each step is one action (2–5 minutes):

- "Write the failing test" — step
- "Run it to make sure it fails" — step
- "Implement the minimal code to make the test pass" — step
- "Run the tests and make sure they pass" — step
- "Commit" — step

## No Placeholders

Every step must contain the actual content an engineer needs. These are **plan failures** — never write them:

- "TBD", "TODO", "implement later", "fill in details"
- "Add appropriate error handling" / "add validation" / "handle edge cases"
- "Write tests for the above" (without actual test code)
- "Similar to Task N" (repeat the code — the engineer may be reading tasks out of order)
- Steps that describe what to do without showing how (code blocks required for code steps)
- References to types, functions, or methods not defined in any task

This rule is identical in both modes. In beans mode, "the engineer reading tasks out of order" is the typical case (tasks are picked up via `beans next` independently), so self-containment matters even more.

## Task Body Template

Use this template for the body of each task — a markdown plan task in markdown mode, a `task` bean's body in beans mode:

````markdown
**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test.py`

- [ ] **Step 1: Write the failing test**

```python
def test_specific_behavior():
    result = function(input)
    assert result == expected
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pytest tests/path/test.py::test_name -v`
Expected: FAIL with "function not defined"

- [ ] **Step 3: Write minimal implementation**

```python
def function(input):
    return expected
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pytest tests/path/test.py::test_name -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add tests/path/test.py src/path/file.py
git commit -m "feat: add specific feature"
```
````

Every code step shows the actual code. Every command step shows the exact command and expected output.

## Markdown Mode

Write the plan to `docs/specs/plans/YYYY-MM-DD-<feature>.md` (user preferences for plan location override this default).

**Header (required at top of the file):**

```markdown
# [Feature Name] Implementation Plan

**Goal:** [One sentence describing what this builds]

**Architecture:** [2–3 sentences about approach]

**Tech Stack:** [Key technologies/libraries]

**Spec:** `docs/specs/YYYY-MM-DD-<topic>.md`

---
```

Each task uses the Task Body Template above, prefixed with `### Task N: [Component Name]`.

After writing the file, run the Self-Review (below). Then point the user at the plan and stop — the plan is the handoff.

## Beans Mode

Map the spec to beans as follows:

### 1. Epic

```bash
beans create --json "<feature name>" \
  -t epic \
  -d "$(cat <<'EOF'
**Goal:** <one sentence>

**Architecture:** <2-3 sentences>

**Tech Stack:** <key libraries>

**Spec:** docs/specs/YYYY-MM-DD-<topic>.md
EOF
)" \
  -s todo
```

Capture the returned `id` — this is `<epic-id>`.

### 2. Features (one per major component)

For each component identified in the File Structure section of the spec:

```bash
beans create --json "<component name>" \
  -t feature \
  --parent <epic-id> \
  -d "<paragraph stating the component's responsibility and which files it owns>" \
  -s todo
```

Capture each returned id.

### 3. Tasks (one per upstream-style "Task N")

For each bite-sized task within a feature:

```bash
beans create --json "<task title>" \
  -t task \
  --parent <feature-id> \
  -d "$(cat <<'EOF'
<Task Body Template content — Files block plus the - [ ] step list with code/commands inline>
EOF
)" \
  -s todo
```

### 4. Ordering dependencies

Where the spec or task structure declares "Task B depends on Task A finishing first", capture it explicitly:

```bash
beans update --json <task-b-id> --blocked-by <task-a-id>
```

Don't infer ordering from list position alone — only encode dependencies the spec actually requires. Over-blocking turns `beans ready` into a serial queue when many tasks are independent.

### 5. Self-Review across the tree

Fetch the whole tree in one shot:

```bash
beans query --json '{ bean(id: "<epic-id>") { title body children { id title body children { id title body } } } }'
```

Apply the Self-Review checklist (next section). Fix issues with:

```bash
beans update --json <id> --body-replace-old "<exact text>" --body-replace-new "<replacement>"
```

### 6. Handoff

Print the tree and tell the user:

> Plan ready in beans (epic `<epic-id>`). Start with `beans next` or `beans ready`. Each task bean's body is self-contained — pick one up cold and follow its checklist.

Stop. The beans tree is the handoff. Do not invoke any other skill.

## Self-Review

After the plan is written (markdown mode) or the beans tree is created (beans mode), look at the output with fresh eyes against the spec. This is a checklist you run yourself — see `references/plan-reviewer-prompt.md` for the full version.

1. **Spec coverage** — skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps and fill them in.
2. **Placeholder scan** — search for the patterns from the No Placeholders section above. Fix them.
3. **Type consistency** — do the types, method signatures, and property names you used in later tasks match what you defined in earlier tasks? A function called `clearLayers()` in task 3 but `clearFullLayers()` in task 7 is a bug.

If you find issues, fix them inline. No need to re-review your own fixes — just fix and move on.

## Remember

- Exact file paths always
- Complete code in every step — if a step changes code, show the code
- Exact commands with expected output
- DRY, YAGNI, TDD, frequent commits
- The bean body (or plan section) must stand alone — assume the reader picks it up cold
