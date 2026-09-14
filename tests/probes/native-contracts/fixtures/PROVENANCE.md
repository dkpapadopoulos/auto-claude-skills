# Fixture provenance

**Every fixture in this directory is excerpted from a retained real trace. None is
hand-written.** A hand-written fixture only proves the classifier agrees with the test
author's idea of the stream format — which is how the audit's earlier probe shipped a
vacuous validity control, and why `TESTS-TODO.md` makes this the first rule.

Source traces are retained on `codex/sdlc-composition-audit` at `d831b7b`, under
`.audit-private/`. **Those files are untracked** — they exist on disk in that worktree
and are not recoverable from git. The excerpts here are the durable copy.

Absolute paths were sanitised (`/Users/...` → `/Users/SANITISED`, temporary workspace
paths → `/tmp/SANITISED-WORKSPACE`). Nothing else was rewritten.

## Source traces

| Key | Path under `.audit-private/` | sha256 |
|---|---|---|
| b3 | `native-conformance-2026-09-14/b3/B3-synthesis-with-dispatch/stdout.jsonl` | `bc2e1e13953981ff8805608d1629bb32f39cd16fb4b8d5349f817fe85958db8e` |
| a3 | `native-conformance-2026-09-14/control/A3-control-no-consultation/stdout.jsonl` | `79c55f7f2ef52afd418ef4de533739fb8d26650f68684373c150fc82e52e58ec` |
| a2 | `native-conformance-2026-09-14/main/A2-standalone-panel/stdout.jsonl` | `67de4ab8a7c90f8b3719c3ecdd3630db90eb0147b7f2ad985dfbc154cd0cb056` |
| r4 | `catalog-v3-2026-09-13/prepared/runs/smoke/minus-specialist/r4/stdout.jsonl` | `7acd603050aa69f4d4f5cb30df833e72f10046e27dd322abf82cb028f28920dd` |

## Fixtures

| Fixture | Case | Source | Derivation |
|---|---|---|---|
| `succeeded-and-refused.jsonl` | successful invocation; attempted but refused | b3 | Excerpt: `init`, the `panel` call and its result, the `synthesize` call and its refusal, the `result` event. Verbatim. |
| `vacuous-absence.jsonl` | vacuous success | a3 | The control run entire, 8 events. Verbatim. |
| `provider-truncation.jsonl` | provider truncation | r4 | Excerpt: `init`, the first four assistant/user events, the `result` event carrying `subtype: "success"` with `is_error: true` and *"You've hit your session limit"*. Verbatim. |
| `no-result.jsonl` | missing result | b3 | **Constructed** by truncation: the real stream with the `synthesize` `tool_result` dropped, leaving a `tool_use` unmatched. `TESTS-TODO.md` specifies this construction. |
| `duplicate-results.jsonl` | duplicate results | b3 | **Constructed** by duplication: the real `panel` `tool_use`/`tool_result` pair emitted twice under distinct ids. |
| `absence-without-precondition.jsonl` | supports the "absence with no precondition" assertion | a2 | The A2 run entire, 23 events: it recorded "did not synthesize" while no perspectives existed to synthesize. Verbatim. |

## Why `duplicate-results.jsonl` is constructed

No retained trace contains a duplicate call. Every `stdout.jsonl` under
`.audit-private/` (41 files) and every `.jsonl` under the audit's
`docs/research/2026-09-11-sdlc-composition/` tree was scanned for a repeated `Skill`
invocation or a repeated `tool_result` per `tool_use_id`; there are none.

That is consistent with how the defect was found. `progress-2026-09-12.md` records it
as an independent-review finding — "duplicate successful calls could produce a false
negative-pair conclusion" — not as a trace observation. The audit's own test for it,
`native/test_native.py::test_duplicate_native_call_is_not_single_invocation`,
hand-writes its rows, which is precisely what this directory's rule forbids; those
tests were therefore not ported.

Duplication of a real pair keeps every byte sourced from a retained trace and puts the
construction in the same class as the sanctioned truncation above. The alternative —
inducing a duplicate in a live paid run — was rejected as costly and not reliably
reproducible.
