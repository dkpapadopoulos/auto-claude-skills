# Design — closing the source-region ERR-trap bypass (#192)

## The defect, precisely

`hooks/openspec-guard.sh` line 6 is `trap 'exit 0' ERR`. That is correct and deliberate: a gate that cannot run must never block. The trap's problem is not that it exists, it is *where it can fire*.

Bash fires the ERR trap for a simple command that returns non-zero, with documented exemptions — a command in the test of an `if`, a non-final operand of an `&&`/`||` list, any pipeline element but the last. #137 leaned on the second exemption, writing every source as `. lib && command -v fn && FLAG=true || true`. That makes the `.` builtin a non-final operand, so **the source's own status** cannot fire the trap.

It says nothing about the commands *inside* the sourced file. Those execute as ordinary top-level commands in the caller's shell, under the caller's trap, with no exemption. So:

```
. lib && FLAG=true || true      # lib contains: false
                                # -> `false` fires ERR -> exit 0 -> empty stdout
```

Empty stdout is the whole severity. A PreToolUse hook communicates a decision by printing one JSON object; printing nothing is how it says "no opinion". So a broken lib and a deliberate allow are the same bytes, and the push goes through.

## Measurement

Repro harness: full-tree copy as a disposable `CLAUDE_PLUGIN_ROOT` (never a bare `/tmp` copy of the hook — the guard derives `_PLUGIN_ROOT` from `$0` and a bare copy fabricates the difference under test), clean verdict seeded so routing-governance does not mask the cells, `git push origin HEAD` payload, one fault at a time.

At `b05925c`: healthy `deny`; `return 1` handled; `false`, command-not-found and `X="$(cd /nope && pwd)"` each **empty stdout**, for both `session-token.sh` and `phase-evidence.sh`. The full 36-cell matrix in the new test reproduces it for all six sourced libs at both injection points.

## Why a function, and a trap clear, and both

`_guard_load` clears the trap around the source and restores it. That is what the issue asks for and it survives someone later adding `set -E` to this hook.

Independently, it is a *function*, and bash does not inherit an ERR trap into a function without `set -E`. Measured on 3.2.57 (macOS `/bin/bash`), sourcing the same failing lib:

```
top level          -> TRAPPED
inside a function  -> continues, reaches end
trap cleared       -> continues, reaches end
```

Either mechanism alone closes the defect. Both are kept because the cost is one line and the failure mode is a silent gate bypass — the class of defect where a plausible-looking refactor ("this doesn't need to be a function") silently restores the hole.

## What the fix does NOT do

It does not repair a broken lib. With the trap cleared, sourcing simply *continues* past the failing command, so the lib may be partially loaded. Callers keep their `command -v <fn>` checks and their #198 degradation notes. The guarantee is narrow and worth stating exactly: **the guard lives long enough to reach a decision, and to announce what it could not check.**

## Injection point decides the outcome, and both are pinned

- **early** (fault before the definitions): sourcing continues, every function is defined anyway, the guard reaches the *healthy* decision. This is the fix working.
- **late** (fault after the definitions): the fault is also the source's last command, so the source's exit status is non-zero. #137's `_guard_load … && FLAG=true` form reads that as "did not load" even though every function is present, and the guard degrades exactly as it does for an absent lib — announced (#198), never silent.

The `late` outcome is a **status-predicate** question, not a trap question. Switching those call sites to a `command -v`-only predicate would gate more in this case — but #198 explicitly considered and rejected that change at the `branch-ledger.sh` site, because a lib that sources cleanly and defines nothing currently DENIES, and the `command -v` form would flip that cell to ALLOW. The two shapes pull in opposite directions:

| predicate | sources clean, defines nothing | complete, last command fails |
|---|---|---|
| status-only (today) | gates (deny) | falls open, announced |
| `command -v`-only | falls open | gates |

Neither dominates, the trade was already settled once, and #192 is not the change that should reopen it. So the test asserts the documented behaviour rather than a decision this fix has no business making. Both baselines are captured from the real guard in the same run — never hand-written — so a cell is pinned to what the producer actually emits.

## Rejected alternatives

**Put `_guard_load` in `hooks/lib/`.** Sourcing a lib in order to make lib-sourcing safe leaves the first source — the one that loads the helper — unprotected, which is exactly the defect. The helper is inline, and extending the fix to another hook means copying it deliberately.

**Widen `tests/test-hook-source-guards.sh` instead.** The issue forbids this and it is right to: that lint is static and inspects call sites, and it stayed green through every silent allow in the table. Widening it would relabel the same coverage rather than add any.

**Clear the trap once, near the top, and restore before the decision path.** Fewer edits, but the region is not contiguous — the guard sources libs at line 169 and again at 1251, with the entire push decision in between. A single region either does not cover the later sites or covers the decision path, and covering the decision path is worse than the bug.

**Scope creep to the other ERR-trap hooks.** `skill-gate.sh` denies too, but a silent exit there costs skill sequencing, not an outbound action; `skill-completion-hook.sh` fails in the safe direction (unrecorded evidence makes the push gate deny *more*). Recorded by name in the lint's scope note so the residue is visible rather than implied.
