# Frozen Pilot Artifact Hashes

Recorded: 2026-09-18 (revised 2026-09-19 — see "Revision" below)

This file is the pre-registration record for the design-seed pilot. Git history and
commit dates are rewritable and are not a trusted timestamp on their own; pushing this
file to the shared remote is what makes "pre-registered" mean something — that push is
Task 7 Step 5 of `docs/plans/2026-09-18-design-seed-pilot-plan.md`, not a step of this
file, which contains only Steps 3 and 4 below.

**Nothing listed below may change after this file is pushed without making this
pre-registration v2** (a new HASHES.md, a new date, and an explicit note of what
changed and why).

## Revision, 2026-09-19 — before any push

This file has **not** been pushed to the shared remote (`git ls-remote --heads
origin` lists no pilot branch at the time of writing), so the sentence above has
not yet bound and this is a re-record rather than a v2. It is noted here in full
anyway, because a pre-registration whose amendments are silent is not one.

**What changed:** `scripts/pilot-capture.sh` only — `737634b3…` → `1d8feccb…`.
Every other hash in the table is byte-identical to the previous revision.

**Why:** the script rendered the judged artifact with the network live, so an
artifact containing a remote `<link>`, `<img>`, `fetch()` or `WebSocket`
performed **egress during capture** — once per colour-scheme pass, before any
human previewed the file, with nothing in any pilot output showing it. That
defeats the carrier the design leans on for the `private_data` residual ("no
private store exists in the arm worktrees … plus the human preview"): a beacon
that fires before anyone looks is not covered by anyone looking. Capture now
aborts every non-local request and runs the browser behind a dead proxy.
Measured against a local server: **8 requests reached it before, 0 after**, with
both PNGs still produced. Regression: the egress cell in
`tests/test-pilot-capture.sh`, verified to FAIL on the unfixed script.

**Why the frozen capture parameters are unaffected:** nothing in the rendering
contract moved — viewport, `deviceScaleFactor`, colour-scheme emulation,
animation/transition/caret suppression and the pinned Playwright version are
unchanged. What changed is what the renderer is permitted to fetch. An artifact
that obeys `brief.md` (no remote references) is captured byte-identically; one
that does not was never a valid pilot artifact.

## Artifact hashes (sha256, `shasum -a 256`)

| Path | sha256 | Frozen at (repo, commit) |
|---|---|---|
| `openspec/changes/design-seed-capability/pilot/rubric.md` | `62f0b5351a163b7c1835fe00dce0cf3321160e8a4908ec0ce8b1b25574358503` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `openspec/changes/design-seed-capability/pilot/brief.md` | `165924c0014e6b9b5d2e6363146010aaa40f494083398376e2a0df47e495b052` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `openspec/changes/design-seed-capability/pilot/budget.md` | `8ab5d14392798d603f045a9db30f043f15f45be45b14e3904d871869a6663c58` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `openspec/changes/design-seed-capability/pilot/advance-disclosures.md` | `74f4cfddb917504e6657900fea9d4c3faddc9f553f3e8f36a95d9dac7cf411c6` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `scripts/pilot-egress-check.sh` | `863bf5d26353173dd769126d75dd857ffd5d464eee08a16a6d216b28403f2e03` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `scripts/pilot-capture.sh` | `1d8feccb444e2a3bf18e30f431eb34fd97c20f4c94e424c925daedc77be93acc` | auto-claude-skills @ `53f37de5831ca5c7598bd40d14b875f47323a54e` |
| `tests/fixtures/design_seed_pilot/review_report_envelope.json` | `c4c7dcd6c99ae3f21f0230b29c443292624e8cb96c31e83e967f6e498f35fadf` | Dion @ `3fbd89a` (base commit the fixture was generated from; see #211 note below) |
| `.claude/hooks/pilot-arm-deny.py` | `f23aae0630e9623da8e9875080c0621ce18c001dd93cceed9b56ec82551d4139` | Dion @ `8364c076bd16e28210a4ed2d7071ff321b01e40b` |

The two `scripts/` rows were added in the 2026-09-18 revision. The safety control
and the capture parameters determine what the pilot refuses to send and what the
judges are shown, so they are part of the frozen apparatus in exactly the way the
four `pilot/` documents are. They were named in prose before and had no hash,
which meant they could change without the record noticing.
`.claude/hooks/pilot-arm-deny.py` joins them for the same reason: it is now the
arms' capability boundary.

## Repo base commits

| Repo | Branch | HEAD |
|---|---|---|
| auto-claude-skills | `design-seed-pilot-impl` | `53f37de5831ca5c7598bd40d14b875f47323a54e` |
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

Both `light.png` and `dark.png` were produced, non-empty, and byte-different (`cmp -s`
reported a difference) — confirming `prefers-color-scheme` emulation is live in the
capture backend. Result: **PASS — capture verified.**

**Re-run 2026-09-19, against the revised script.** `scripts/pilot-capture.sh` changed
in this revision, so the result above no longer describes the frozen artifact and was
re-measured from scratch rather than carried forward:

```
captured light.png and dark.png in <tmpdir>/out
CAPTURE_EXIT=0
light.png 12423 bytes, dark.png 12416 bytes
capture verified: two differing PNGs produced
```

Result: **PASS — capture verified against `1d8feccb…`.** The byte counts differ from
the pre-revision run (12035/12118) because the probe page is re-rendered by a browser
launched with a proxy configured; the property being verified — two non-empty,
byte-different PNGs — is unchanged, and capture remains deterministic run-to-run
(asserted by the existing cells in `tests/test-pilot-capture.sh`, which compare two
captures of the same page byte-for-byte).

**Egress verification, new in this revision.** Capture was additionally measured
against a local HTTP server logging every request, using an artifact carrying a remote
`<link>`, a remote `<img>`, a `fetch()` and a `WebSocket`:

```
unfixed script (737634b3…):  8 requests reached the server   (4 shapes x 2 passes)
revised script (1d8feccb…):  0 requests reached the server
both runs: light.png and dark.png produced, exit 0
```

Result: **PASS — capture performs no egress.** The regression cell asserts this against
a real server and was confirmed to FAIL on the unfixed script, so it is not a test that
merely agrees with the code.

## Step 4: full suite result

**auto-claude-skills** — re-run in full for the 2026-09-19 revision, against the final
content of `53f37de…`, with no concurrent suite run in the worktree.
`bash tests/run-tests.sh`, run to completion. The runner's own final summary:

```
============================================
  Files run:    153
  Files passed: 153
  Files failed: 0
============================================
All test files passed.
SUITE_EXIT=0
```

Result: **PASS — 153/153 files passed, 0 failed.** The count is unchanged from the
previous revision because this revision adds cells to an existing file rather than a
new file; `tests/test-pilot-capture.sh` went from 6 to 8 passing cells within it.

**Dion** — **not re-run for the 2026-09-19 revision.** That revision touches
`auto-claude-skills` only; no Dion-side file in the hash table changed, and the Dion
row in "Repo base commits" is unmoved. The result below is the 2026-09-18 run, carried
forward and labelled as such rather than restated as fresh. `bash scripts/ci.sh`
(`uv sync --frozen`, ruff, pyright `src/`,
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
- (2026-09-18) The Step 3 capture verification was not re-run for that revision,
  on the grounds that `scripts/pilot-capture.sh` was unchanged. **That no longer
  holds:** the script changed on 2026-09-19, and Step 3 was re-measured from scratch
  against the new hash — see "Re-run 2026-09-19" above. This bullet is kept rather
  than deleted so the record shows the carried-forward claim and its expiry.
- (2026-09-19) Dion's gate was not re-run — see the Dion note under Step 4 for why,
  and for the fact that the figures there are carried forward.
- The egress block is verified against the request shapes the regression cell drives
  (remote `<link>`, `<img>`, `fetch()`, `WebSocket`) plus a wider one-off probe
  (`<script src>`, `@font-face`, `<iframe>`, `sendBeacon`, `<a ping>`, `EventSource`,
  `XMLHttpRequest` — 20 requests, all blocked). It is **not** a proof of no egress:
  UDP-based paths such as WebRTC/STUN are untested, and DNS resolution behaviour under
  the proxy was not measured. Those are named in the beaconfix report as residual
  rather than claimed closed.
