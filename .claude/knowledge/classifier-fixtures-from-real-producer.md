---
type: convention
title: Derive an output-classifier's test fixture from the real producer, never hand-write it
description: A classifier that string-matches another component's output must be tested against that component's actual bytes — a hand-written fixture only proves the classifier agrees with the test's idea of the format, and silently passes while production misclassifies 100% of cases.
tags: [testing, hooks, json, string-matching, false-positive, instrumentation]
source: scripts/push-gate-capture.sh:79
timestamp: 2026-07-27T09:51:55Z
---

When code classifies another component's output by **string matching** (rather
than structural parsing), the format is an implicit contract. A test that
fabricates the producer's output cannot verify that contract — it only proves
the classifier agrees with the test author's assumption.

## The measured failure

`scripts/push-gate-capture.sh` classified the push gate's replayed decision:

    case "${_rout}" in
      *'"permissionDecision":"deny"'*) _replay_decision="deny" ;;

`hooks/openspec-guard.sh` emits that JSON via `jq -n`, which **pretty-prints**:

    "permissionDecision": "deny"      # space after the colon, own line

The compact needle could never match. Every replayed deny fell through to the
next branch and was classified `allow` — and per the documented semantics
`deny` + `allow` means *"drift confirmed"*. So the instrument built to diagnose
an intermittent false-deny defect reported a **false positive on 100% of
denies** from merge onward: all 24 field records, across 5 plugin versions and
3 guard checksums, with `capture_error: null`. Reading them at face value said
the plugin was drifting; the uncorrupted `guard_cksum` channel independently
showed no drift.

The regression test passed throughout, because it stubbed the guard with
hand-written **compact** JSON:

    _stub "$HOME/stub-deny.sh" 'printf "%s\n" "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\"}}"'

## Why this one place, and where else to look

An audit of every in-repo consumer found this was the **only** instance. The
reason is structural and worth internalising: everywhere else the repo parses
another component's output with `jq -r`, which is format-agnostic by
construction and cannot have this bug. `push-gate-capture.sh` is the one place
that *could not* fork `jq` — it runs inside the guard's hardened EXIT trap,
where forks are deliberately minimised.

> Wherever a performance or safety constraint forces string matching instead of
> structural parsing, that is exactly where a format assumption hides silently.

Aggravating factor in this repo: `hooks/openspec-guard.sh` emits **two**
formats — `printf` (compact) for advisories, `jq -n` (pretty) for denies. Any
future string-matching consumer starts pre-loaded with the trap.

## What to do

1. **Prefer structural parsing.** `jq -r '.a.b'` cannot have a format bug. Reach
   for string matching only when a real constraint forbids the fork.
2. **Derive the fixture from the producer.** Extract the real emitter rather
   than retyping its output, so the test follows production automatically:

        _DENY_EMIT="$(grep -m1 -F 'permissionDecision":"deny"' hooks/openspec-guard.sh | sed 's/^[[:space:]]*//')"

3. **Assert end-to-end against the real component at least once.** Stub cases
   can only prove internal consistency; exactly one assertion driving the actual
   producer is what catches format drift.
4. **Normalise before matching** when you must string-match:
   `_rnorm="${_rout//[[:space:]]/}"` — pure bash, no fork, format-agnostic.
5. **Never change the producer to satisfy an observer.** The fix belongs in the
   diagnostic, not in the enforcement path it watches.

Same family as [[behavioral-eval-subject-read-contamination]]: in both, the test
passed while measuring something other than what its author believed.
