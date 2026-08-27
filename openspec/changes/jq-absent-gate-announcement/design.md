# Design — announcing the jq-absent gate (#213)

## What was actually wrong

Three causes compound, and any one fixed alone leaves the gate silent:

1. **The payload parser.** `openspec-guard.sh` greps only `"command"` in its no-jq fallback, never `transcript_path`, so `_TRANSCRIPT` stays empty, no token resolves, and the hook takes the empty-token exit.
2. **Every check that reads recorded evidence parses it with jq.** Seeding a token so one *does* resolve still reaches no trustworthy conclusion.

   **This was first written as "every gate body is behind `command -v jq`", which is false, and the error was load-bearing.** `routing-governance` is gated on `_VERDICT_OK` — whether `verdict.sh` loaded — not on jq. `verdict.sh` sources fine without jq, so the leg RAN; every predicate under it (`verdict_is_clean`, `verdict_covers_head`, …) reads the artifact with jq and so returned "not clean" for want of a parser rather than for want of a verdict; the leg took its else branch, concluded **deny**, and died at its bare `jq -n`. A decision reached and thrown away. Believing the false premise would have closed this issue with the deny still dying.
3. **Every deny is emitted by `jq -n`** (7 sites). Without jq the guard has no way to emit a deny even where a gate body concluded it should. Only `_emit_advisory` had a printf fallback.

That third cause is what makes "just make it work without jq" a non-starter. The gate's decisions are JSON in and JSON out; the only way to run it without jq is to hand-roll a JSON parser and a serialiser in Bash 3.2 and then trust both with a security decision.

## Why #198 did not catch it

`_DEGRADED_MSG` had no entry for a missing `jq` at all, and the empty-token exit announced only when `_TOKEN_LIB_OK != true`. Without jq the token lib is **healthy** — it simply never received a transcript — so the exit classified this as the ordinary "not a driven session" case and stayed quiet.

The state that most warrants the sentence "the ENTIRE push gate was skipped and this command was not gated" was precisely the state in which that sentence was suppressed.

## The "nothing was gated" licence

`CLAUDE.md` reserves that wording for the empty-token exit, deliberately: elsewhere it would be an over-report, because the composition-chain REVIEW/VERIFY checks read `.completed` straight out of the state file with `jq` and need no lib, so they keep running and keep denying even when every lib is gone. #198 records that claiming otherwise is the *worse* failure — telling the user to distrust a gate that is still holding.

The jq case earns the licence for a stronger reason than the token case: it is `jq` itself that is missing, so the lib-free checks are gone too. There is no leg left running to overstate. That reasoning is recorded here because the next reader will otherwise be right to delete the wording.

## Escaping

Both no-jq emitters interpolate `${_PLUGIN_ROOT}` into a JSON string:

- `_emit_advisory` used `tr '\n"' ' '` — newlines and quotes, not backslashes.
- The final `_WARNINGS` emitter used `tr '\n' ' '` — newlines only, so any quote broke it, and one live note already contains `\"warn\"`.

A malformed object is dropped by the harness, which returns the guard to silence *inside the code added to end silence*. The red test proves it: with a plugin root of `…/we ird\path`, the pre-fix guard emitted a JSON object containing a raw `\p` that `jq -e .` rejects.

`_json_escape` handles backslash **before** quote — the other order would double the escapes the quote pass just added — and replaces control characters rather than escaping them, since `\u00XX` handling is not worth hand-rolling in Bash 3.2 for an advisory string.

The character class is `[:cntrl:]`, and the first cut got that wrong: it named `\n\r\t` only, which is three of the thirty-two bytes JSON forbids unescaped. A raw BEL still produced output `jq -e .` rejects — the same silent-drop failure this helper exists to prevent, merely rarer. It was found by driving the real helper over an adversarial byte table rather than by reading it, and a reviewer independently produced the same list (`\x01 \x07 \x08 \x0b \x0c \x1b \x1f`). Code that looks obviously correct is exactly the code that earns a table.

## The deny emitter

Cause 3 needed its own fix, not just an advisory. All seven deny sites used a bare `jq -n`, so a leg that had already decided to deny died at the emitter. `_emit_deny` gives them a printf fallback through the same escaper.

Two things about it are deliberately narrow. First, **it does not license denying without jq**: `routing-governance` gained a `_JQ_OK` precondition in the same change, because its deny was reached only through predicates that could not read their input, which is a false block manufactured by the missing tool. Emitting that deny would have converted a silent allow into a confident wrong answer — worse, not better. Second, **after the fix no deny path is reachable without jq at all**, so the fallback is defence-in-depth rather than a live path; describing it as restoring denies would be an overclaim.

`mutate-then-push` is the one deny that could legitimately fire without jq — `command_git_mutate_before_push` is pure string parsing — but it carries its own long-standing `command -v jq` precondition. Un-gating it would newly deny compound commit-and-push on jq-less machines: a real enforcement increase, out of scope for a change about announcing, and recorded here rather than flipped in passing.

## What this does NOT buy

Visibility, not enforcement. A jq-less machine still pushes ungated. The honest framing is that the gate has never worked there and now says so once per gated command; installing `jq` is the fix, and the advisory says that.

## Testing notes

The control is the load-bearing half of every cell. Two PATH shims are built from the real `PATH`, differing by exactly one symlink, and the test asserts that the no-jq shim really lacks `jq` **and** really still has `git` — a shim broken in some unrelated way produces the same empty output as the defect, and the test would pass while measuring nothing. This is the same mistake made once during the original investigation, where a shim self-check reported "test invalid" and the numbers looked identical either way.

JSON validity is checked by the *test's* jq over output produced by a guard that had none.

One assertion was written as a lowercase paraphrase (`not gated`) of the producer's actual wording (`was NOT gated`) and failed while the feature worked — the same class as a hand-written fixture: the test agreeing with itself rather than with the code. It now matches the producer.
