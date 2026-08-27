## Why

With `jq` absent from `PATH`, `hooks/openspec-guard.sh` allowed **every** gated command, silently. Empty stdout, which the harness cannot distinguish from a deliberate allow. Issue #213.

Measured with a PATH shim omitting **only** `jq` — everything else identical, one variable — against a `git push origin HEAD` payload with a clean verdict seeded at HEAD:

| PATH | `command -v jq` | guard stdout |
|---|---|---|
| shim without jq | ABSENT | **empty (0 bytes)** |
| same shim, jq relinked | PRESENT | `deny`, 460 bytes |

The control is the load-bearing half: it proves the shim is otherwise sound and that jq is the only difference. Reproduces identically at `b05925c` and after #192, so it is neither new nor a #192 regression.

`CLAUDE.md` calls jq "optional at runtime", so a jq-less machine is a *supported configuration* — one on which this gate had never worked and never said so.

## What Changes

Not making the gate work without jq (that means trusting a hand-rolled JSON parser with a security decision), and not denying when jq is missing (that violates the invariant the gate is built on — a check that cannot run must never block — and would brick every push on a jq-less machine). The gate still falls open. It now **says so**.

- **A degradation note for a missing `jq`**, recorded after the fast path (so only genuinely gated commands carry it) and before token resolution (so it is present at the empty-token exit).
- **The empty-token exit no longer suppresses it.** That exit announced only when the token *lib* had failed. Without jq the token lib is perfectly healthy — it just never got a transcript to parse — so the single state that most warrants "nothing was gated" was the one state that stayed quiet.
- **The no-jq payload fallback now also greps `transcript_path`.** Necessary but explicitly **not sufficient**: with a token resolved the guard reaches no verdict it can trust, because every check that reads state parses it with jq. Done so the advisory names the right session, not as the fix. (It also moved the failure: with a token resolving, the guard got as far as routing-governance — see below.)
- **`_emit_deny`, and a `_JQ_OK` precondition on routing-governance.** The claim that "every gate body is behind `command -v jq`" — carried in the issue and in the first draft here — is **false**, and finding that out changed the fix. `routing-governance` is gated on `_VERDICT_OK` (the lib loading), not on jq. Without jq it therefore RAN, and every verdict predicate under it reads the artifact with jq, so each returned "not clean" for want of a parser rather than for want of a verdict. It then denied — and died at its bare `jq -n` emitter, ERR trap, exit 0, empty stdout. A decision reached and thrown away. Two separate corrections follow: the leg is now `_JQ_OK`-gated, because a check that cannot run must never block and that deny was a false block manufactured by the missing tool; and all seven deny sites now emit through `_emit_deny`, which has a printf fallback, so a deny that IS legitimate can never again be silently discarded.
- **`_json_escape` for both no-jq emitters.** They interpolated `${_PLUGIN_ROOT}` into JSON with `tr` sanitisers that dropped newlines and (in one) quotes, but never backslashes. A plugin path containing a backslash produced unparseable JSON, the harness dropped the object, and the guard went silent again — inside the code path added to stop it being silent. The final `_WARNINGS` emitter was worse: it stripped only newlines, and one live degradation note contains `\"warn\"`.

## Capabilities

### Modified Capabilities

- `pdlc-safety`: a push gate that cannot run must announce that fact, including when the reason is a missing external tool rather than a broken library; and an announcement that is not valid JSON is not an announcement.

## Impact

- `hooks/openspec-guard.sh` — one flag, one note, one widened condition, one escaping helper, one deny emitter, one added precondition. **No change on the jq-present path**: the pinned byte-identical healthy-control fixture (`tests/fixtures/guard-lib-fault/healthy-control.json`) still matches, and both `jq -n` emitters are untouched.
- `tests/test-push-gate-jq-absent.sh` — new, 33 assertions including an adversarial `_json_escape` table driven over the helper extracted from the guard. Mutation matrix re-measured on the final tree (an earlier "11 of 19" figure implied a green baseline that did not exist — the test was red at HEAD from the routing-governance defect, so the number described nothing): baseline **33/33**; delete the whole jq-note block ⇒ **6 fail**; remove `_JQ_OK` from routing-governance ⇒ **8 fail** (the defect this change exists to close is now detected); guard reverted to `main` ⇒ **14 fail**; `_json_escape` neutered to identity ⇒ **9 fail**; remove `_JQ_OK` from verify-hardening ⇒ **0 fail** — that precondition is a defensive statement of intent and is NOT covered, which is worth knowing rather than counting as tested. The delete row is the one that matters: before the routing-governance fix, deleting the entire feature changed no test result, because the assertions that would catch it were already permanently red. Two published figures before this were harness artifacts — one from a mutation that left the guard unparseable, one from running the suite in a copy with no `.git` so routing detection could not fire. Mutations must be checked for `bash -n` and run where the legs under test can actually execute.
- Two assertions were vacuous and are now guarded: `jq -e` ERRORS on empty input, so the "carries no permissionDecision" pair recorded PASS for output that did not exist, and the control's `assert_not_contains "jq" ""` is trivially true because a denying control has no advisory at all.
- `verify-hardening` gained the same explicit `_JQ_OK` precondition. It was already safe without jq, but only because its two jq-reading predicates happen to fail toward allow — and depending on an accident of that kind is exactly how routing-governance came to deny on a verdict it could not read. No behaviour change.
- No change to `_GATE_ENFORCE_LIBS`, the canary manifest, or the drift manifest.

## Residual gaps, recorded not closed

- **The gate genuinely does not run without jq.** This change buys visibility, not enforcement. A jq-less machine still pushes ungated; the user is now told, once per gated command. Verified after the fix: no deny path is reachable without jq, so `_emit_deny`'s fallback is **defence-in-depth rather than a live path** — it exists so the next deny added outside a jq gate cannot silently die the way routing-governance just did. Stated plainly because claiming it restores denies would be an overclaim.
- **`mutate-then-push` remains jq-gated** by its own long-standing precondition, even though `command_git_mutate_before_push` is pure string parsing and needs no jq. Un-gating it would make a jq-less machine start denying compound commit-and-push — a real enforcement increase, and a behaviour change beyond announcing. Left alone deliberately, recorded here rather than silently flipped.
- `phase-attest.sh` is the one `_GATE_ENFORCE_LIBS` member with no degradation note of its own (its consumers are `command -v`-guarded and advisory-only). Belongs to #198's inventory.
- A lib that calls `exit` during source still kills the hook — recorded under `source-region-err-trap`, unchanged here.
