# Frozen Pilot Artifact Hashes

Recorded: 2026-09-18

This file is the pre-registration record for the design-seed pilot. Git history and
commit dates are rewritable and are not a trusted timestamp on their own; pushing this
file to the shared remote is what makes "pre-registered" mean something — that push is
Task 7 Step 5 of `docs/plans/2026-09-18-design-seed-pilot-plan.md`, not a step of this
file, which contains only Steps 3 and 4 below.

**Nothing listed below may change after this file is pushed without making this
pre-registration v2** (a new HASHES.md, a new date, and an explicit note of what
changed and why).

## Artifact hashes (sha256, `shasum -a 256`)

| Path | sha256 | Frozen at (repo, commit) |
|---|---|---|
| `openspec/changes/design-seed-capability/pilot/rubric.md` | `62f0b5351a163b7c1835fe00dce0cf3321160e8a4908ec0ce8b1b25574358503` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `openspec/changes/design-seed-capability/pilot/brief.md` | `165924c0014e6b9b5d2e6363146010aaa40f494083398376e2a0df47e495b052` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `openspec/changes/design-seed-capability/pilot/budget.md` | `8ab5d14392798d603f045a9db30f043f15f45be45b14e3904d871869a6663c58` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `openspec/changes/design-seed-capability/pilot/advance-disclosures.md` | `74f4cfddb917504e6657900fea9d4c3faddc9f553f3e8f36a95d9dac7cf411c6` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `scripts/pilot-egress-check.sh` | `863bf5d26353173dd769126d75dd857ffd5d464eee08a16a6d216b28403f2e03` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `scripts/pilot-capture.sh` | `737634b3c8585d72efc084f3314f247e5e4b4a3a89bee068f36af610bf8cadd0` | auto-claude-skills @ `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| `tests/fixtures/design_seed_pilot/review_report_envelope.json` | `c4c7dcd6c99ae3f21f0230b29c443292624e8cb96c31e83e967f6e498f35fadf` | Dion @ `3fbd89a` (base commit the fixture was generated from; see #211 note below) |
| `.claude/hooks/pilot-arm-deny.py` | `f23aae0630e9623da8e9875080c0621ce18c001dd93cceed9b56ec82551d4139` | Dion @ `8364c076bd16e28210a4ed2d7071ff321b01e40b` |

The two `scripts/` rows are new in this revision. The safety control and the capture
parameters determine what the pilot refuses to send and what the judges are shown, so
they are part of the frozen apparatus in exactly the way the four `pilot/` documents
are. They were named in prose before and had no hash, which meant they could change
without the record noticing. `.claude/hooks/pilot-arm-deny.py` joins them for the same
reason: it is now the arms' capability boundary.

## Repo base commits

| Repo | Branch | HEAD |
|---|---|---|
| auto-claude-skills | `design-seed-pilot-impl` | `ac2bb3daecde0e22405fe1ce20c403e85e0a5c17` |
| Dion | `design-seed-pilot` | `8364c076bd16e28210a4ed2d7071ff321b01e40b` |

**These are the commits the artifacts above were hashed at** — not a claim about what
HEAD is now. This file is committed separately, immediately after, so HEAD at the
moment you read this is one commit ahead of the row above by construction; the row
names where the hashed bytes live, which is the only thing a hash table can honestly
claim. The previous revision recorded `ef6fe587747f3fd447783a2ba96685633de8bc95`,
which was already stale when written — the commit that recorded the hashes was itself
later than the commit named. Re-hash and re-record together, or the row silently names
a tree the hashes were not taken from.

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

Both repos' gates were re-run for this revision, against the final content of the
commits recorded above, with no concurrent suite run in either worktree.

**auto-claude-skills** — `bash tests/run-tests.sh`, run to completion. The runner's own
final summary:

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

**Dion** — `bash scripts/ci.sh` (`uv sync --frozen`, ruff, pyright `src/`,
time-determinism, pytest fast lane):

```
2334 passed, 12 skipped, 883 deselected, 21 warnings in 357.13s (0:05:57)
local CI gate passed
```

Result: **PASS — 2334 passed, 12 skipped, 0 failed.** Dion is gated here because the
arms' capability boundary (`.claude/hooks/pilot-arm-deny.py`) now lives in that repo
and is hashed above; its 12-cell regression
(`tests/design_seed_pilot/test_arm_capability_boundary.py`) runs in that lane.

## Anything not independently re-verified in this task

- The `#211` fixture-equivalence diff (byte-identical report content modulo
  `run_id`/`summary.created_at`/`summary.report_id`) was performed in an earlier
  throwaway worktree per the task brief and is recorded here as reported, not
  re-run from scratch in this task.
- The Step 3 capture verification above was **not** re-run for this revision.
  `scripts/pilot-capture.sh` is unchanged — its hash `737634b3…` is recorded in the
  table for the first time here, and the file is byte-identical to the one that
  verification was performed against — so the earlier result still describes the
  frozen artifact.
