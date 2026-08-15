---
name: writing-claude-directives
description: Use when writing instructions that guide Claude behavior - skills, CLAUDE.md files, agent prompts, system prompts. Covers what earns a place in a directive, token budgets, compliance techniques, discovery, and skill portability.
cc:user-invocable: false
---

# Writing Claude Directives

Modern Claude models are more often over-constrained than under-constrained. Guardrails written for older generations now cost more than they buy: they narrow exploration, and when the same rule appears in several places at different strictness levels, effort goes into reconciling them rather than into the work.

## What earns a place

Three tests. A directive should pass at least one.

**1. Taste, not consensus.** Nothing else tells the model which side of a contested choice you are on. "Declare close to usage", "rule of three before abstracting", "lowercase `failed to X` error fragments" earn their tokens precisely because reasonable codebases disagree about them.

**2. Counteracts a default rather than restating one.** Rules that resist a known tendency — happy-path bias, agreeableness in review, implementing before researching — are the most valuable thing a directive can hold. Rules describing what would have happened anyway are ceremony.

**3. Cheap to say.** Most bloat is elaboration, not rules. "Keep the happy path left-aligned" is one line and does not need a before/after code pair. Cut worked examples and justification paragraphs; keep the rule.

Do not justify a cut with "Claude already knows this." Training data sets the model's prior, and the corpus average includes plenty of code you would reject on sight. Knowing a principle and defaulting to it are different claims.

**When unsure, demote rather than delete.** Moving something into `references/` (see Progressive disclosure, below) is a much cheaper way to be wrong than deleting it.

## Two further grounds for cutting

- **Factually stale** — guidance calibrated to an older model generation that is now wrong, not merely redundant.
- **Duplicated across sources** — the same rule in several files at several strictness levels. State each rule in exactly one place. Conflicting copies force deliberation regardless of whether any single copy is worth keeping.

## Structural rules

**Portability.** A skill is installed independently of any project and runs against arbitrary ones, so it may reference only files shipped inside its own directory. A path pointing into one particular repo resolves nowhere else, and the failure is quiet rather than loud: the model absorbs the read error and carries on without the guidance.

This constrains *skills*. A CLAUDE.md file ships inside the repo it describes, so repo-relative paths are correct there.

**Shared policy gets its own skill.** When two or more skills need the same rule, extract it and have each load it explicitly. Do not nominate one as owner and have the others cross-reference it: load order and co-presence are not guaranteed, and a review skill may well run without the write-code skill ever loading.

## Discovery

The `description` field decides whether Claude finds the skill at all, which makes it the highest-leverage line in the file.

Start with "Use when...", name specific triggers, and write in third person — it is injected into the system prompt. Include the symptoms, error messages, and tool names someone would actually search for.

```yaml
# Vague, first person
description: I help with async testing

# Triggers + action, third person
description: Use when tests have race conditions or timing dependencies - replaces arbitrary timeouts with condition polling
```

## Compliance

**Context over authority.** Explain why a rule exists; the model generalizes from the explanation. "Run tests before committing" carries less than "Run tests before committing — untested commits break CI for the whole team and block other people from merging."

Reserve imperatives for genuine boundaries ("Never commit secrets to version control"). An imperative on every rule marks none of them.

**Close loopholes with context, not volume.** "Write the test first. Code written before its test tends to test the implementation rather than the behavior, which makes refactoring harder later. If you find yourself with untested code, delete it and start with the test."

**Anticipate rationalizations** in discipline-enforcing directives — "this is simple enough to skip", "I already tested manually", "this case is different". Naming them is usually enough to defuse them.

## Structure

**Progressive disclosure.** The main file is an overview plus links; reference files load on demand. This is how a large body of guidance stays cheap — an unread reference costs nothing.

**Lead with what matters most.** Instructions at the start and end of a prompt get the most attention.

**Give the skill something to check against.** A validator, rubric, or test the model can run and loop on beats prose describing the standard — it turns "did I do this right" from a judgment call into a check. This is what `scripts/` is for.

**Match specificity to fragility:**

| Task | Freedom | Style |
| --- | --- | --- |
| Fragile operations | Low | Exact commands, no improvisation |
| Preferred patterns | Medium | Templates with parameters |
| Context-dependent | High | Principles and heuristics |

**XML tags** cleanly delimit multi-part directives (`<task>`, `<constraints>`, `<output_format>`) and double as format indicators. Use them where the structure earns it; markdown is fine elsewhere.

**Match prompt style to desired output.** Markdown in the prompt encourages markdown back; drop it when you want plain text.

## References

Prefer real artifacts to prose descriptions — code, test suites, rubrics, HTML mockups. They carry more signal per token and are unambiguous in a way prose is not.

Subject to the portability rule above: the artifact has to ship inside the skill directory. `references/` and `scripts/` are where it goes. Shipping a copy means it can drift from whatever it was copied from, so prefer artifacts that are self-contained or cheap to regenerate.

## Naming

Gerund form: `writing-plans`, `debugging-errors`. Name by the action or the insight rather than the domain — `condition-based-waiting`, not `async-helpers`.

## Budget

- Frequently-loaded directives: under 200 words
- A skill's main file: under ~150 lines — this is the surface that always loads
- Any single reference file: under ~500 lines
- Reference `--help` instead of documenting flags
- Cross-reference other skills instead of restating them

## Common mistakes

| Mistake | Fix |
| --- | --- |
| Explaining mechanics the model can derive | Omit — but see "What earns a place": knowing is not defaulting |
| Several valid approaches | Pick a default, note the escape hatch |
| Vague triggers | Name symptoms: "tests flaky", "race condition" |
| Nested references | Keep one level deep from the main file |
| Windows paths | Forward slashes always |
| Repo-relative path in a skill | Ship the file inside the skill directory |

## Testing

There is no unit test for a directive. Run the scenario without it and document what fails, add it, then verify the behaviour actually changed.

When trimming, the failure mode is discovering that a rule was load-bearing. So trim, use the result for real work, and watch specifically for the behaviour you cut.
