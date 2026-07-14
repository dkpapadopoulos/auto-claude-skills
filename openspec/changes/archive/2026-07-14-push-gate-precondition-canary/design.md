# Design: push-gate-precondition-canary

## Architecture

Single hook change plus one behavioral test file.

Canary block in `hooks/session-start-hook.sh`, placed after the WARNINGS
array exists and before `WARNING_COUNT` is computed (so it renders through
the existing `Warnings:` channel — no new output surface):

1. Build the component list: `hooks/openspec-guard.sh` + the four
   `hooks/lib/` files the gate sources (`branch-ledger.sh`, `verdict.sh`,
   `git-command.sh`, `session-token.sh`), all under `PLUGIN_ROOT`.
2. Missing-file check: plain `[ -f ]` per component (stat-cheap).
3. Parse check: ONE `/bin/bash -n <all existing files>` fork. On non-zero
   exit, re-run per-file (only then — the unhealthy path may afford forks)
   to name the broken component(s).
4. Append at most one warning:
   `PUSH-GATE CANARY: <names> missing/unparseable — the fail-closed push
   gate silently skips the affected checks (fail-open). Restore to re-arm
   enforcement.` Healthy = zero output.
5. Whole block wrapped fail-open (`|| true` composition, no set -e): a
   canary bug must never break session start.

jq-less path: the existing early-exit MSG string gains one sentence — the
push gate cannot establish evidence without jq and falls open. That path
must stay plain ASCII (no jq available to encode); the constraint is already
documented inline there.

## Trade-offs

- **`bash -n` (parse) vs subshell-source probe — REVISED BY RED TEST:** the
  original decision was parse-only (side-effect-free by construction), but
  the red fixture — deliberately the documented Bash-3.2 killer, a quoted
  operand in `$(( ))` — proved `-n` misses it: that class fails at
  EXPANSION time, not parse time (CLAUDE.md's own gotcha says exactly this).
  Final shape: gate LIBS get a stdio-nulled subshell SOURCE probe (sourcing
  is precisely what the guard does; the libs are function-definition-only,
  and a subshell contains any effects), while `openspec-guard.sh` itself —
  a script that executes and reads stdin — stays parse-only. Runtime-only
  failures in the guard's body remain the (documented) blind spot.
- **Session-start placement vs per-push placement:** warning at push time
  would be tautological (the fail-open paths are exactly the ones that can't
  evaluate); session start is where degradation is readable BEFORE work
  begins. One-line cost per session only when degraded.
- **No auto-repair:** the canary reports, never fixes — repairing hook files
  automatically from a hook is self-modification of the enforcement layer
  (governance non-starter).

## Dissenting views

- The audit's Codex sparring rated F5 medium ("blast high, likelihood
  environmental") — considered folding it into plugin CI instead. Rejected:
  CI validates the REPO's files, not the INSTALLED cache the running gate
  actually sources; the observed failure mode (installed 3.69.2 lagging main
  by two enforcement fixes) is precisely a deployed-environment property
  only a session-start check can see.

## Decisions

1. Component list is hardcoded next to the block with a PAIRED note (same
   precedent as the gating-milestone filter) — a new gate lib must be added
   to the canary list in the same change.
2. Behavioral red-first tests execute the real hook in a temp plugin root
   (healthy silence + two degradation modes + jq-less wording).
3. Trifecta: no new legs (reads local plugin files, writes session context
   only); no agent-safety-review needed.

## Implementation Notes (synced at ship time)

- Built as designed except one TDD-driven revision, recorded above: the red
  fixture proved `bash -n` blind to the Bash-3.2 expansion-time class, so
  libs are source-probed (subshell, stdio-nulled) instead of parse-checked.
- Review (combined code+governance, verdict Yes / APPROVE-WITH-NOTES)
  verified the reordered claims: render path traced end-to-end, all four
  libs confirmed function-definition-only, report-only property confirmed.
  Applied its accuracy note: the canary list covers gate-ENFORCEMENT libs;
  the guard's fifth sourced lib (`consol-marker.sh`, advisory with inline
  fallback) is deliberately excluded and now documented as such.
- Measured healthy-path cost ~10ms (5 probes), within the session-start
  budget; the cold-run 2s baseline is pre-existing registry-build weight.
