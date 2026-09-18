# Frozen Pilot Artifact Hashes

Recorded: 2026-09-18

This file is the pre-registration record for the design-seed pilot. Git history and
commit dates are rewritable and are not a trusted timestamp on their own; pushing this
file to the shared remote is what makes "pre-registered" mean something — see Step 5.

**Nothing listed below may change after this file is pushed without making this
pre-registration v2** (a new HASHES.md, a new date, and an explicit note of what
changed and why).

## Artifact hashes (sha256, `shasum -a 256`)

| Path | sha256 | Frozen at (repo, commit) |
|---|---|---|
| `openspec/changes/design-seed-capability/pilot/rubric.md` | `62f0b5351a163b7c1835fe00dce0cf3321160e8a4908ec0ce8b1b25574358503` | auto-claude-skills @ `ef6fe587747f3fd447783a2ba96685633de8bc95` |
| `openspec/changes/design-seed-capability/pilot/brief.md` | `165924c0014e6b9b5d2e6363146010aaa40f494083398376e2a0df47e495b052` | auto-claude-skills @ `ef6fe587747f3fd447783a2ba96685633de8bc95` |
| `openspec/changes/design-seed-capability/pilot/budget.md` | `8ab5d14392798d603f045a9db30f043f15f45be45b14e3904d871869a6663c58` | auto-claude-skills @ `ef6fe587747f3fd447783a2ba96685633de8bc95` |
| `openspec/changes/design-seed-capability/pilot/advance-disclosures.md` | `2e05d5f3f447c6dabc64a85bd8aeaae3f6a079c6bbaddbb6f06901eee6c91f81` | auto-claude-skills @ `ef6fe587747f3fd447783a2ba96685633de8bc95` |
| `tests/fixtures/design_seed_pilot/review_report_envelope.json` | `c4c7dcd6c99ae3f21f0230b29c443292624e8cb96c31e83e967f6e498f35fadf` | Dion @ `3fbd89a` (base commit the fixture was generated from; see #211 note below) |

## Repo base commits

| Repo | Branch | HEAD |
|---|---|---|
| auto-claude-skills | `design-seed-pilot-impl` | `ef6fe587747f3fd447783a2ba96685633de8bc95` |
| Dion | `design-seed-pilot` | `eb17003a5333db94fffd60eb035458d6469bf093` |

The Dion fixture (`tests/fixtures/design_seed_pilot/review_report_envelope.json`) was
generated against `3fbd89a` — `fix(ingest): an unfinished run is never a snapshot
(#242) (#243)` — which is an ancestor of both Dion's `main` and the pilot branch HEAD
above.

## Measured: `#211` is content-equivalent to the pinned base for this fixture

Dion's `#211` — `fix(optimizer): holdings come from the newest statement, not the
newest row (#211) (#245)`, commit `4f2ae22` — merged to Dion's `main` during
pre-launch, after the fixture's pinned base (`3fbd89a`) and not reachable from it or
from the pilot branch.

The fixture was regenerated on top of `4f2ae22` in a throwaway worktree and diffed
against the frozen fixture above. **Measured result: the report content is
byte-identical.** The only fields that differ are `run_id`, `summary.created_at`, and
`summary.report_id`.

This means the pinned base `3fbd89a` is content-equivalent to post-`#211` main for
this fixture — stated here as a measurement (naming `4f2ae22` as the commit checked
against), not as a caveat that results should be "read accordingly."

## Step 3: real-capture verification (blocking, not advisory)

`tests/test-pilot-capture.sh` SKIPs and exits 0 when no capture backend is available,
so a green `run-tests.sh` does not by itself prove screenshot capture is possible.
Judging needs matched light/dark screenshots, so this was verified directly against
`scripts/pilot-capture.sh` with a synthetic light/dark probe page before launch:

```
captured light.png and dark.png in <tmpdir>/out
CAPTURE_EXIT=0
PNGs present and non-empty
capture verified: two differing PNGs produced
```

Both `light.png` (12035 bytes) and `dark.png` (12118 bytes) were produced, non-empty,
and byte-different (`cmp -s` reported a difference) — confirming `prefers-color-scheme`
emulation is live in the capture backend. Result: **PASS — capture verified.**

## Step 4: full suite result

`bash tests/run-tests.sh` (auto-claude-skills, at HEAD `ef6fe58`), run to completion in
the foreground with no concurrent suite run in the worktree. The runner's own final
summary:

```
============================================
  Files run:    153
  Files passed: 153
  Files failed: 0
============================================
All test files passed.
SUITE_EXIT=0
```

Result: **PASS — 153/153 files passed, 0 failed.**

## Anything not independently re-verified in this task

- The `#211` fixture-equivalence diff (byte-identical report content modulo
  `run_id`/`summary.created_at`/`summary.report_id`) was performed in an earlier
  throwaway worktree per the task brief and is recorded here as reported, not
  re-run from scratch in this task.
