---
name: brainstorming
description: "You MUST use this before any creative work — creating features, building components, adding functionality, or modifying behavior. Explores user intent, requirements, and design before implementation; uses plannotator for structured option/spec review and hands off to writing-plans for execution decomposition."
cc:allowed-tools: Bash(plannotator:*)
---

# Brainstorming Ideas Into Designs

Help turn ideas into fully formed designs and specs through natural collaborative dialogue.

Start by understanding the current project context, then ask questions one at a time to refine the idea. Once you understand what you're building, surface 2–3 approaches via plannotator for structured review, then present and refine the design, write a spec, and re-run plannotator on the spec before handing off to `writing-plans`.

<HARD-GATE>
Do NOT invoke any implementation skill, write any code, scaffold any project, or take any implementation action until you have presented a design and the user has approved it. This applies to EVERY project regardless of perceived simplicity.
</HARD-GATE>

## Anti-Pattern: "This Is Too Simple To Need A Design"

Every project goes through this process. A todo list, a single-function utility, a config change — all of them. "Simple" projects are where unexamined assumptions cause the most wasted work. The design can be short (a few sentences for truly simple projects), but you MUST present it and get approval.

## Checklist

Complete these in order:

1. **Explore project context** — files, docs, recent commits
2. **Ask clarifying questions** — one at a time, understand purpose/constraints/success criteria
3. **Propose 2–3 approaches** → write to a file, run **plannotator options review** (see [Plannotator integration](#plannotator-integration))
4. **Present design** — in sections scaled to their complexity, get inline approval after each
5. **Write spec** — save to `docs/specs/YYYY-MM-DD-<topic>.md` (user preferences for spec location override this default)
6. **Spec self-review** — placeholder/contradiction/scope/ambiguity scan; see `references/spec-reviewer-prompt.md`
7. **Plannotator final-spec review** — address annotations, re-run until approved
8. **Hand off to `writing-plans` skill** — terminal state

**The terminal state is invoking `writing-plans`.** Do NOT invoke any other implementation skill from here.

## The Process

**Understanding the idea:**

- Check out the current project state first (files, docs, recent commits)
- Before asking detailed questions, assess scope: if the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag this immediately. Don't spend questions refining details of a project that needs to be decomposed first.
- If the project is too large for a single spec, help the user decompose into sub-projects: what are the independent pieces, how do they relate, what order should they be built? Then brainstorm the first sub-project through the normal design flow. Each sub-project gets its own spec → plan → implementation cycle.
- For appropriately-scoped projects, ask questions one at a time to refine the idea.
- Prefer multiple choice questions when possible, but open-ended is fine too.
- Only one question per message — if a topic needs more exploration, break it into multiple questions.
- Focus on understanding: purpose, constraints, success criteria.

**Exploring approaches:**

- Compose 2–3 different approaches with trade-offs, leading with your recommended option and explaining why.
- Write the options to a file and invoke the plannotator options review — see [Plannotator integration](#plannotator-integration) for the file template and exact command. Plannotator is the review surface for this step; file-anchored annotations capture structured feedback that inline chat replies lose.

**Presenting the design:**

- Once you understand what you're building, present the design.
- Scale each section to its complexity: a few sentences if straightforward, up to 200–300 words if nuanced.
- After each section, ask whether it looks right and wait for the user to confirm before moving on. This conversational pattern is specific to the design walkthrough — options and the final spec both go through plannotator, not chat.
- Cover: architecture, components, data flow, error handling, testing.
- Be ready to go back and clarify if something doesn't make sense.

**Design for isolation and clarity:**

- Break the system into smaller units that each have one clear purpose, communicate through well-defined interfaces, and can be understood and tested independently.
- For each unit, you should be able to answer: what does it do, how do you use it, and what does it depend on?
- Can someone understand what a unit does without reading its internals? Can you change the internals without breaking consumers? If not, the boundaries need work.
- Smaller, well-bounded units are also easier for you to work with — you reason better about code you can hold in context at once, and your edits are more reliable when files are focused. When a file grows large, that's often a signal that it's doing too much.

**Working in existing codebases:**

- Explore the current structure before proposing changes. Follow existing patterns.
- Where existing code has problems that affect the work (e.g., a file that's grown too large, unclear boundaries, tangled responsibilities), include targeted improvements as part of the design — the way a good developer improves code they're working in.
- Don't propose unrelated refactoring. Stay focused on what serves the current goal.

## Plannotator Integration

This skill uses [plannotator](https://plannotator.ai/docs/commands/annotate/) for two structured review gates: the **options review** (after composing 2–3 approaches) and the **final-spec review** (after the spec self-review pass). In both cases the user gives file-anchored feedback, not inline chat replies.

### Options review

After composing 2–3 approaches, write them to `docs/specs/YYYY-MM-DD-<topic>-options.md`. Use one `## Approach N: <name>` heading per option, each with **Summary**, **Pros**, **Cons**, and a **Recommendation** at the bottom of the file naming the recommended approach with one-sentence reasoning.

Then invoke:

```bash
plannotator annotate --gate --json docs/specs/YYYY-MM-DD-<topic>-options.md
```

Set the Bash tool timeout to `1800000` ms (30 minutes) so the user has enough time to review.

The command returns JSON of the form `{"decision": "approved"|"annotated"|"dismissed", "feedback": "..."}`. Handle each branch:

- **`approved`** — delete the options file (`rm -f <path>`), then proceed with the recommended approach as written. Move to "Present design". The options file is a transient review artifact; only the spec is worth retaining.
- **`annotated`** — the `feedback` field contains numbered annotation blocks. Treat each as an instruction: revise the options file inline (or pivot to a different recommended approach). Re-run `plannotator annotate --gate --json` on the revised file. Loop until `approved`.
- **`dismissed`** — the user wants a fresh take. Rewrite the options from scratch (different framings, different trade-offs) and re-invoke plannotator. Do NOT fall back to inline questioning.

### Final-spec review

After the spec self-review pass (see `references/spec-reviewer-prompt.md`), invoke:

```bash
plannotator annotate --gate --json docs/specs/YYYY-MM-DD-<topic>.md
```

with the same 30-minute timeout. Handle the JSON decision identically:

- **`approved`** — hand off to `writing-plans`.
- **`annotated`** — for each annotation, apply the Summarize → Evaluate → Act loop from the local `plannotator:user-code-review` skill: summarize the feedback in one line, evaluate whether it's valid (push back if it would introduce a bug or conflict with an explicit constraint), apply the fix or explain the disagreement. After all annotations are addressed, re-run plannotator. Loop until `approved`.
- **`dismissed`** — treat as a request to rework the spec. Revise substantively (often this means going back to the design conversation) and re-invoke plannotator.

### Note on the existing hook

Plannotator's home-manager hook auto-fires only on `ExitPlanMode`. The two `plannotator annotate` invocations above are independent manual calls during brainstorming — they don't conflict with the hook because brainstorming runs outside plan mode.

## After Approval

Once the final-spec review returns `approved`, invoke the `writing-plans` skill. It will detect whether `beans` is on `$PATH` and either emit a beans hierarchy (epic → feature → task) or write a markdown plan to `docs/specs/plans/`.

Do NOT invoke any other implementation skill from this skill.

## Key Principles

- **One question at a time** — don't overwhelm with multiple questions
- **Multiple choice preferred** — easier to answer than open-ended when possible
- **YAGNI ruthlessly** — remove unnecessary features from all designs
- **Explore alternatives** — always propose 2–3 approaches before settling
- **Incremental validation** — present design, get approval before moving on
- **Be flexible** — go back and clarify when something doesn't make sense
