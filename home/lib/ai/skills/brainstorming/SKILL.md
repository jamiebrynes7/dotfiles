---
name: brainstorming
description: "You MUST use this before any creative work — creating features, building components, adding functionality, or modifying behavior. Settles intent, requirements, and design through rounds of questions with recommended answers, writes a spec reviewed via plannotator, and hands off to writing-plans for execution decomposition."
cc:allowed-tools: Bash(plannotator:*)
---

# Brainstorming Ideas Into Designs

Turn an idea into an approved spec by settling every design decision once, in rounds of questions, then writing the decisions down for a single structured review.

**Gate:** take no implementation action — no code, no scaffolding, no implementation skill — before the spec is approved, and after approval hand off to `writing-plans`, which is the only next step. This holds for "simple" work too: a config change or a one-function utility is where unexamined assumptions waste the most effort. The spec can be a few sentences; it still gets approved.

## Checklist

Complete these in order:

1. **Explore project context** — files, docs, recent commits
2. **Question rounds** — settle every decision, including any fork in approach; see [Question rounds](#question-rounds)
3. **Write spec** — save to `docs/specs/YYYY-MM-DD-<topic>.md` (user preferences for spec location override this default); see [Writing the spec](#writing-the-spec)
4. **Spec self-review** — placeholder/contradiction/scope/ambiguity scan; see `references/spec-reviewer-prompt.md`
5. **Plannotator spec review** — address annotations, re-run until approved
6. **Hand off to `writing-plans`** — the terminal state

## Exploring context

- Check the current project state first (files, docs, recent commits). Explore the existing structure before proposing changes, and follow its patterns.
- Assess scope before asking detailed questions. If the request describes multiple independent subsystems (e.g., "build a platform with chat, file storage, billing, and analytics"), flag it immediately and help the user decompose it: the independent pieces, how they relate, and the build order. Then brainstorm the first sub-project; each gets its own spec → plan → implementation cycle.
- Where existing code has problems that affect the work (a file that's grown too large, tangled responsibilities), include targeted improvements in the design. Don't propose unrelated refactoring.

## Question rounds

Map the design as a **decision tree**: every decision branches into the decisions that depend on it. Purpose, constraints, and success criteria sit near the root.

Work the tree in rounds. Each round, ask every question that can be answered *now* — whose prerequisites are already settled — as one numbered batch, then wait for the answers. Hold back any question whose answer depends on another question still open; it belongs to a later round. Each round's answers unblock the next set of questions.

Give every question a recommended answer.

**Ask through your structured question tool** — `AskUserQuestion` in Claude Code, or your assistant's equivalent — so the user picks answers instead of typing them:

- Each question offers its candidate answers as options, recommended one first and marked "(Recommended)", with each option's trade-offs in its description. Even an open question (purpose, constraints) gets your best-guess answers as options; the user can always write their own.
- If the tool caps questions per call, split the round across consecutive calls before moving on — the round is still one batch, and the next round waits for all of it.

Only when no such tool is available, ask the round as plain text, wording each question so that replying "yes" accepts its recommendation (➡️):

```
❓ **Q1** - **<question title>**: <question body — context, and the choices if there are several>

➡️ <your recommended answer>

---

❓ **Q2** - ...
```

- **A fork in approach is a question.** When there are genuinely different ways to build it, ask which one, with each option's trade-offs and your recommendation. If there's only one sensible approach, there's no question — state it in the spec.
- **Facts are your job; decisions are the user's.** Never ask the user something you could look up (code, docs, tool behaviour, upstream APIs). Dispatch a subagent to find it (or look it up yourself if you can't dispatch one), and keep asking the questions that don't depend on that lookup — only questions downstream of it wait.
- **Record only what was answered.** A question the user skipped stays open into the next round. A bare "yes" to the round accepts every recommendation in it.
- **Done** when no open decisions remain and nothing is silently assumed. Close the last round by asking whether you've reached a shared understanding, so the spec isn't drafted on a misread.

## Writing the spec

Write the spec straight from the settled decisions. Make sure it covers:

- **Architecture** — the units involved and how they fit together
- **Components** — what each does, how it's used, what it depends on
- **Data flow** — how information moves between them
- **Error handling** — what can fail and what happens when it does
- **Testing seams** — where the behaviour will be verified. Prefer existing seams (checks, test suites, harnesses) over new ones, and as few as possible.

Scale each part to its complexity: a sentence when it's straightforward, a few paragraphs when it's nuanced. If covering one of these needs a decision the rounds didn't settle, run another question round — don't decide it in the spec.

The spec records decisions and verified facts — interfaces, contracts, option shapes, upstream behaviour you confirmed — not file-by-file layouts or implementation code. Those go stale before the work lands; the implementer works them out against the code as it is then. Inline a snippet only when it encodes a decision more precisely than prose (a schema, a type shape).

### Specs are point-in-time

A spec records what was decided, and why, on a date. It is not living documentation: once work lands, the code is the source of truth, and durable conventions belong in the project's `CLAUDE.md`/`AGENTS.md`, not the spec.

- Start every spec with a short header:

  ```markdown
  Date: YYYY-MM-DD
  Supersedes: docs/specs/<older-spec>.md §<sections>   <!-- omit if none -->
  ```

- Do not edit an older spec to track what was actually built. When returning to partially implemented work, or changing an earlier decision, write a new spec that covers only the new decisions and names what it supersedes.
- Explore the code before relying on an older spec's description of it — where they differ, the code wins.

## Plannotator spec review

The spec is the user's first full view of the design, and [plannotator](https://plannotator.ai/docs/commands/annotate/) is where they review it: file-anchored annotations capture structured feedback that inline chat replies lose. After the self-review pass (see `references/spec-reviewer-prompt.md`), invoke:

```bash
plannotator annotate --gate --json docs/specs/YYYY-MM-DD-<topic>.md
```

The review can take the user a while. Run the command in the background if your shell tool notifies you when a background command exits, and allow it at least 30 minutes; otherwise run it in the foreground with a 30-minute (`1800000` ms) timeout.

The command returns JSON of the form `{"decision": "approved"|"annotated"|"dismissed", "feedback": "..."}`. Handle each branch:

- **`approved`** — hand off to `writing-plans`.
- **`annotated`** — the `feedback` field contains numbered annotation blocks. For each, apply the Summarize → Evaluate → Act loop from the local `plannotator:user-code-review` skill: summarize the feedback in one line, evaluate whether it's valid (push back if it would introduce a bug or conflict with an explicit constraint), apply the fix or explain the disagreement. After all annotations are addressed, re-run plannotator. Loop until `approved`.
- **`dismissed`** — treat as a request to rework the spec. Revise substantively — often this means another question round — and re-invoke plannotator.

Plannotator's home-manager hook auto-fires only on `ExitPlanMode`. This manual `plannotator annotate` call doesn't conflict with it, because brainstorming runs outside plan mode.

## After approval

Once the spec review returns `approved`, invoke the `writing-plans` skill. It breaks the spec into vertical-slice tickets, reviews the breakdown with the user, and either emits an epic with task tickets in beans or writes a markdown plan to `docs/specs/plans/`.
