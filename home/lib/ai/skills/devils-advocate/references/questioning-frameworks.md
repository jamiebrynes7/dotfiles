# Questioning Frameworks

Structured ways to interrogate a decision, plan, or diff. Each is a move, not a ceremony — take the questions, skip the workshop.

## Steel-Manning — do this first, always

Before critiquing, construct the best case FOR the approach: name the exact decision, list the constraints the author faced (time, backward compatibility, team expertise, existing patterns), then state what would have to be true for it to be optimal — "this is the right call IF...". Now check whether those conditions hold.

This is not politeness. It catches the case where the approach is correct and you're the one missing context, and it makes the surviving critique specific enough to act on.

- "What's the strongest argument for keeping this exactly as it is?"
- "Under what conditions would this be the ideal approach?"
- "What constraints made this the pragmatic choice?"
- "What am I missing about the context that would make this reasonable?"

## Pre-Mortem — assume it already failed

Frame it as fact: "It is six months from now. This shipped and caused a serious incident." Then write specific failure *narratives*, not vague risks — "the migration ran 47 minutes, exceeded the maintenance window, and left the database inconsistent because...". Rank by likelihood × impact, trace each back to the assumption or missing test in the current plan, and name the preventive action.

The reframe matters: "IF this failed, here's how" surfaces concerns that "this is wrong" suppresses.

- New endpoint: "This caused an outage and paged someone at 3am. What happened?"
- Migration: "It failed halfway on production. What was different about prod?"
- Launch: "Users are furious, tickets tripled. What did we get wrong about how they'd use it?"
- Dependency upgrade: "It broke production silently — no errors, wrong behaviour. What did our tests not cover?"
- Optimization: "It made things worse under real load. What traffic pattern did we miss?"

## Inversion — what would guarantee failure?

Define the opposite goal ("guaranteed data loss"), enumerate specific ways to achieve it, then verify the plan actively prevents each one. Every gap is a finding.

For an auth system, the inverse list runs: store passwords in plaintext, never expire sessions, return different errors for unknown-user vs wrong-password, allow unlimited attempts, put tokens in query params, trust client-side role claims. For a deployment: no rollback plan, irreversible migrations, no staged rollout, no post-deploy verification, undocumented manual steps.

- "If we wanted to guarantee corruption in this pipeline, what would we do? Are any of those present?"
- "What's the fastest way a malicious insider could exploit this?"
- "What would make this impossible to debug in production?"

## Socratic Questioning — six probes

**Clarification** — vague terms hide complexity.
- "What exactly do you mean by scalable / robust / simple?"
- "What does 'done' look like? What's the acceptance test?"
- "When you say 'handle errors gracefully', what does the user actually see?"

**Assumptions** — most design flaws are untested beliefs.
- "What are we assuming about the input data that might not hold?"
- "Are we assuming this third-party service is always available?"
- "What if this table grows 100x — does the query plan still work?"
- "Is there an assumption about ordering or timing here?"

**Evidence** — how do we know this is true?
- "What data supports this design choice?"
- "Has this been tested under production-like conditions, or estimated?"
- "How do we know the current implementation is actually the bottleneck?"
- "Where did the requirement for X come from? Can we verify it?"

**Perspectives** — who else sees this?
- "How does the on-call engineer experience this at 3am?"
- "How does this look from the attacker's perspective?"
- "What would a new team member think reading this code?"
- "What does support need when this breaks?"

**Implications** — follow it forward.
- "If we do this, what does it commit us to maintaining?"
- "What becomes harder to change after we ship?"
- "If this succeeds wildly, what breaks first?"
- "What other systems are in the blast radius?"

**Meta** — is this the right question?
- "Are we solving the symptom or the root cause?"
- "Is this our problem to solve, or should it be handled elsewhere?"
- "What would we do if we couldn't use this approach at all?"
- "Are we optimizing for the right metric?"

## Reverse Five Whys — trace the decision to its motivation

Ask "why this approach?" repeatedly, moving from surface rationale → underlying concern → real vs. assumed constraint → whether that constraint is actually fixed → whether this is the best way to address the root concern. Use it when the rationale is "best practice" or "how we've always done it."

It reliably exposes complex solutions aimed at symptoms: *microservices → independent deployability → different cadences → payments needs compliance review* — which a CI approval gate solves without splitting the architecture.

## Other lenses worth a pass

- **Missing data** — separate measured from assumed: real latency, actual traffic on this path, production error rates, load-tested vs. estimated.
- **Alternatives** — generate before judging: not building it at all, a different architecture, splitting it into two simpler problems, the simplest version that's still useful.
- **Process** — are we spending time on the highest-risk area? What decision are we actually making? How will we know which option was better?

## Recommended sequence

Steel-man → clarify → reverse five whys → inversion → pre-mortem → implications. Understanding before challenge: it builds the credibility that makes the critique land, and it filters out stylistic preferences before they reach the user.

| Situation | Reach for |
| --- | --- |
| Reviewing a plan before execution | Pre-mortem, then inversion |
| Evaluating one technical decision | Reverse five whys, then steel-man |
| "This feels wrong but I can't say why" | Inversion, then pre-mortem |
| Challenging a confident proposal | Steel-man first, then assumptions |
| Reviewing someone else's code | Steel-man first, then clarification |
