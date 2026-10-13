# The design method

How to get a good interface out of Claude, and keep it good as it grows. Five steps. The
seed (`../assets/design-seed/`, resolved from this file — see its `ADOPT.md`) is step 0's
output; this document is the rest.

It needs **no** external design-system connector. Claude Design is a separate, optional
lane, and it comes after this method rather than replacing a step of it: an adopted
`design/` can be published there as a design system, and "Taking it to Claude Design" in
`../assets/design-seed/ADOPT.md` records what one attempt carried over and what it did
not. The `DesignSync` tool is not a way to do step 2. As read on 2026-10-13, its own
description limits it to syncing an existing component library into a design-system
project and says never to use it to make a design. Either way the files in the repo are
the contract, never the connector.

## 0. Foundations, once per project

Adopt the seed. Do not start designing screens before a project has tokens and a
styleguide: a model with no role tokens invents values, and a model with no reference
imitates whatever templated default it saw most. This is the single highest-leverage
half-hour in the whole method.

## 1. Ground the question

Write down, in the project, the things the designing agent **cannot see**:

- the real data shape, including the states that are awkward — missing values, blocked
  outcomes, stale snapshots, zero rows;
- what the person using this screen is trying to decide;
- the constraints that are not negotiable (what must never be shown, what must never be
  inferred, what the screen may not trigger).

Do not restate the styleguide here. It already has that. Carry only what it cannot infer.

**A brief is a request, not a decision.** Pose the problem and the open questions; do not
pre-decide the layout. Pre-deciding is how you get one option and call it a choice.

## 2. Explore — at least two real alternatives

Build thin variants on **identical** fixture data, varying information hierarchy, not
colour. Two is a real minimum; three is better; one is not exploration.

Use frozen fixtures, never live data — both because it keeps the comparison honest and
because a screen that can reach production data during design is a data-egress path
nobody reviewed.

Cover the hard states in every variant. A variant that only renders the happy path has
not been designed, it has been sketched.

## 3. Decide — and write down why

Compare the variants against the question from step 1, not against taste. Record the
decision and the losing options in the project's design intent (an OpenSpec change here;
a design doc elsewhere). Invoke `prototype-lab` at this step to run the comparison — do
not wait for it to have been routed by the prompt, and do not invent a second comparison
format.

## 4. Implement

Reference roles, never literals. Build only what the chosen screen needs. Run
`design/checks/token-lint.sh` before claiming it is done.

## 5. Verify in a browser, with evidence that fits the claim

Open it. Look at it in both themes, at a narrow width, and with the keyboard only.
`runtime-validation` orchestrates the automatable parts (Playwright, axe, Lighthouse,
visual regression) — that skill owns UI evidence; this method does not duplicate it.

**Match the evidence to the claim.** A screenshot is observation; a check is bounded
evidence; another model is another opinion. They are not interchangeable, and there is no
quota of rounds to perform. If you claim contrast is fixed, show the contrast result. If
you claim the layout survives 360px, show it at 360px.

## When to change the styleguide

When a real screen needed something the styleguide could not express — that is the signal.
Add the role, run the lint, update the reference. Do not add tokens speculatively: an
unreferenced token is a maintenance cost with no reader.

## What this method does not do

It does not pick your stack, and it deliberately names none: the tokens are plain CSS
custom properties, so they work under any framework, and a recommendation here would age
faster than the method. It does not generate components. It does not review code —
`agent-team-review` and `security-scanner` own that. And it does not replace looking at
the thing yourself, which remains the only step nobody can delegate.
