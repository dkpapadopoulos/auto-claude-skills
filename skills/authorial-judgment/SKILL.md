---
name: authorial-judgment
description: Use when authoring or de-generic-ifying persuasive prose — essays, blog posts, op-eds, newsletters, talks, or a "make this not sound like AI" rewrite — to apply a post-draft authorial-judgment revision pass. NOT for README/API-docs, specs/changelogs, or code.
---

# Authorial Judgment

A revision lens for prose that is technically correct, well-structured, and still
dead. LLM prose tends to be too smooth, too complete, too linear, too certain, too
eager to resolve every thought. This lens makes judgment visible instead of faking
imperfection.

**Use this as a post-draft pass** — after the premise is settled, before the final
style pass. Draft first (or take the user's draft), then run the six moves below.

**When NOT to use:**
- README, API docs, tutorials — reference writing *should* be complete and linear.
- Specs, changelogs, release notes, status updates — procedural writing *should* be
  certain and literal. The moves below would corrupt it.
- Code, commits, tests, config.

## The hard gate: real texture or clean prose

Human texture comes from exactly three sources:
1. Real details the author supplied.
2. Real uncertainty in the evidence.
3. Real editorial judgment about what matters.

If none of those exist, **keep the prose clean.** Do not decorate the absence. Never
fabricate uncertainty, lived experience, memory, cognitive bias, or knowledge gaps to
sound human. This gate outranks every move below.

## The six moves

1. **Authorial position, not persona.** Write from what the author has actually seen,
   believes, is skeptical of, or refuses to overclaim — not an invented biography.
   *Weak:* "As someone who spent years in boardrooms…" *Better:* "The boardroom version
   is simple: everyone agrees in principle, then avoids the one decision that makes the
   strategy real."

2. **Real objection = real friction.** Add friction only by handling the pushback a
   smart reader would actually raise. Ask: what would they reject, think is ignored, or
   consider too easy? Then answer it briefly. Not random detours.

3. **Deliberation only when earned.** Show the thought; don't announce it. Kill
   announced-thought phrases: "let's unpack," "it's worth noting," "as we delve
   deeper," "the deeper point is," "before we proceed." Use a visible turn only when the
   claim is complex, contested, or easy to oversimplify.

4. **Sharpening re-articulation.** Revisit a key idea at most once, and only when the
   second pass adds a mechanism, a consequence, or a more precise noun. Restating the
   same idea in prettier words is repetition, not depth.

5. **Rhythm follows thought.** Vary sentence and paragraph shape to match the argument,
   never mechanically. If several sentences start the same way or every claim is
   followed by an example in the same pattern, restructure — lead one sentence with the
   consequence, another with the constraint; break a long explanation before the reader
   has to work.

6. **AI-inversion refusal.** Before finishing, name the move a default LLM would make
   here — the safe hook, the tidy symmetrical conclusion, the reflexive metaphor, the
   paragraph included only to sound complete, the overstated claim — and refuse it.
   Choose the sharper alternative.

## Also

- **Skip the baseline; name the blind spot.** Don't explain what the target reader
  already knows, and don't use false-authority cues ("as is generally understood," "the
  discerning reader"). Say "the familiar version is only half the problem" instead.
- **Earn the aside.** A digression is allowed only if it makes the main point sharper —
  reveals a mechanism, exposes a tradeoff, or connects to a concrete operating reality.
- **No decorative metaphor.** An image must clarify the mechanism, not sound nice.

## Final review

Before the style pass, ask: Is the argument doing real work? Is the smart reader's
objection addressed? Is any uncertainty real rather than performed? Did any
re-articulation deepen the idea? Is there any fake memory, persona, or flaw? **Could a
smart reader replace this with a generic article and lose nothing?** If yes, revise.

For failure-mode names and repairs, see `references/red-flags.md`.
