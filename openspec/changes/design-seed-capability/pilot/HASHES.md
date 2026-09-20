# Frozen Pilot Artifact Hashes

Recorded: 2026-09-18 (revised 2026-09-19; **v2 on 2026-09-20** — see "v2" below)

This file is the pre-registration record for the design-seed pilot. Git history and
commit dates are rewritable and are not a trusted timestamp on their own; pushing this
file to the shared remote is what makes "pre-registered" mean something — that push is
Task 7 Step 5 of `docs/plans/2026-09-18-design-seed-pilot-plan.md`, not a step of this
file, which contains only Steps 3 and 4 below.

**Nothing listed below may change after this file is pushed without making this
pre-registration v2** (a new HASHES.md, a new date, and an explicit note of what
changed and why).

## v2, 2026-09-20 — the first revision after this file bound

Both pilot branches are on the shared remote, so the sentence above has bound and
this **is** a v2, not a re-record. It is declared as one.

**No v1 results are being discarded, because none exist.** Neither arm has run; no
artifact, screenshot, judge response or score has been produced or seen. The pooling
rule exists to stop a protocol being tuned against observed results — there is
nothing here to tune against. What follows was found by verifying the table below
against the bytes on the branches, before launch.

### What changed, and why

**(1) `.claude/hooks/pilot-arm-deny.py` — the row was wrong when this file bound.**

| | commit | sha256 |
|---|---|---|
| recorded in v1 | Dion `8364c07` | `f23aae06…` |
| actually on the pushed branch | Dion `3e6902a` | `9172e24f…` |

Dion `3e6902a` — *"fix: scope the pilot-arm deny hook to pilot-arm worktrees"*,
2026-09-19 13:33 — changed that file by +97 lines. ACS `4c15261` — 13:40, seven
minutes later — documented the change in `design.md` and **did not update this
row**. Both branches were then pushed in that state. So this file bound while
naming bytes that were not on the branch, for the artifact it itself calls "the
arms' capability boundary".

This is the exact failure the v1 text warns about two sections down — *"Re-hash and
re-record together, or the row silently names a tree the hashes were not taken
from"* — recurring one artifact later. The row now names the bytes that will
actually run. **The hook is not being changed to match the record; the record is
being corrected to match the hook**, and `3e6902a` is kept because the unscoped
hook it replaced was wrong.

**(2) The Dion base moves to `7d56694` — the hook suite could commit over the
repository being pushed.**

Dion's checkouts are linked worktrees, and git exports `GIT_DIR`/`GIT_WORK_TREE` to
its hooks in exactly that case. `.githooks/pre-push` runs the whole suite through
`scripts/ci.sh`, so `tests/test_pre_push_hook.py` inherited them — and `git -C` does
not override them: it changes directory, not the repository. The throwaway fixture
therefore operated on the repository being pushed: `git init <tmp_path>` silently
reinitialised it, `git add .` staged the deletion of every tracked file, and the
commit landed on the branch being pushed. **Two such commits reached
`design-seed-pilot`** (author `t <t@t>`, subject `init`, ~236k deletions), preserved
as `rescue/unknown-init-16eedb8` and `rescue/unknown-init-97b2fe9`.

This had to be fixed **before** launch and **in the base**, not around it: the arms
work in worktrees forked from this base, and a push from any of them would have run
the unfixed suite against that arm's branch. A pilot cannot measure what arms
produce in worktrees of a repo that commits over them unbidden.

`7d56694` touches `tests/test_pre_push_hook.py` and `CLAUDE.md` only. **No hashed
artifact moved** — verified, not assumed: `git diff --name-only 3e6902a 7d56694`
lists those two paths, and both Dion rows below are byte-identical to v1
(`9172e24f…` was already the truth; `c4c7dcd6…` is unchanged). Every
`auto-claude-skills` row is byte-identical to v1 as well.

**(3) Arms are dispatched as headless `claude -p` sessions, not as subagents —
because the capability boundary is inert for subagents.**

The design names `.claude/hooks/pilot-arm-deny.py` as "the arms' capability
boundary" and hashes it for that reason. Measured before launch, it does not fire
for a subagent of the orchestrating session. One probe subagent, instructed to
report plainly:

```
CLAUDE_PROJECT_DIR = UNSET      pwd = the auto-claude-skills checkout
WebFetch  https://example.com -> SUCCEEDED
WebSearch "example domain"    -> SUCCEEDED
pilot-arm-deny marker         -> never emitted
```

Three independent causes, any one sufficient: Dion's `.claude/settings.json` is
never loaded, because a subagent belongs to the orchestrating session and not to
the worktree's project; the hook's own command line is
`python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/pilot-arm-deny.py"`, which with that
variable unset names a nonexistent path; and `_is_arm_context()` reads
`CLAUDE_PROJECT_DIR` and falls back to the HOOK PROCESS's cwd — the session's
directory, never the arm's worktree. The file's docstring reasons that "an arm
cannot rewrite `CLAUDE_PROJECT_DIR` for its own already-running session", which is
true and beside the point: the harness never sets it for a subagent.

Task 8 Step 4 of the plan already ruled on this state — "an `rc=0` ... means the
boundary is not there" — so a faithful probe halts the launch. **It is recorded
here rather than quietly worked around**, because a pilot that ships its safety
control as prose is the failure the control was written to prevent.

**The remedy is measured, not assumed.** The same worktree, hook and tool, varying
only the dispatch mechanism:

| dispatch | `CLAUDE_PROJECT_DIR` | `WebFetch` |
|---|---|---|
| subagent of the orchestrating session | unset | **succeeded** |
| headless `claude -p`, cwd = the worktree | set by the harness | **denied**, with the `pilot-arm-deny:` marker |

The headless leg is also the pair's positive control: it proves the hook, the
settings wiring and the worktree are sound, so the subagent leg succeeding is
genuine inertness rather than a broken probe.

Each arm is therefore launched as its own headless session rooted in its worktree.
**What this does not change:** the arms remain two fresh agents with disjoint
context, one per worktree off the same base, receiving identical brief, fixture,
model and budget. If anything the isolation is stronger — a headless session
cannot see the orchestrating conversation at all, where a subagent inherits a
dispatch prompt from it. No criterion, rubric dimension, budget rule, judging
procedure or pre-registered outcome is touched. The hashed hook file itself is
**unmodified**; what changed is how the arms are started, so that the file is
actually in force.

### What did not change

The protocol did not. `rubric.md`, `brief.md`, `budget.md`,
`advance-disclosures.md`, `pilot-egress-check.sh` and `pilot-capture.sh` are
byte-identical to v1, and no arm, criterion, budget rule, judging procedure or
pre-registered outcome has been touched. This v2 corrects one stale row and moves
the Dion base by one commit that no hashed artifact depends on.

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
| `.claude/hooks/pilot-arm-deny.py` | `9172e24fdb5026b7aa7b330b3a9b63d18549243d7188e1ea0c531665fc16aca3` | Dion @ `7d56694d49c74bdbc8c62469fea53844b1bb21b7` (v2: corrected — v1 named `f23aae06…` @ `8364c07`, which was already superseded) |

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
| Dion | `design-seed-pilot` | `7d56694d49c74bdbc8c62469fea53844b1bb21b7` |

The Dion row moved in v2 (`8364c07…` → `7d56694…`); see v2 item (2). The
`auto-claude-skills` row is unchanged.

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

**auto-claude-skills — re-run in full for v2.** `bash tests/run-tests.sh`, run to
completion against the working tree at `4c15261` plus this file's v2 edit (no test
reads `HASHES.md`, so the run describes the code at `4c15261`):

```
  Files run:    153
  Files passed: 153
  Files failed: 0
All test files passed.
SUITE_EXIT=0
```

Result: **PASS — 153/153 files passed, 0 failed.** Unchanged from the previous
revision, as expected: v2 edits documentation only on this side.

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

**Dion — re-run in full for v2**, because v2 moves the Dion base
(`3e6902a` → `7d56694`) and a result measured at another commit may not be carried
across that move. `bash scripts/ci.sh` at `7d56694`, run to completion:

```
2346 passed, 12 skipped, 883 deselected, 21 warnings in 367.65s (0:06:07)
ci: recorded pass for 7d56694d49c74bdbc8c62469fea53844b1bb21b7
local CI gate passed
```

Result: **PASS — 2346 passed, 12 skipped, 0 failed.** The count rises from 2334 by
12: eleven cells added by `3e6902a` (`tests/design_seed_pilot/test_arm_capability_boundary.py`)
and one added by `7d56694` — the regression cell for the inherited-`GIT_DIR` defect
in v2 item (2), which was confirmed to FAIL with the fix's three call sites reverted
before being accepted as passing.

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
- (2026-09-19) Dion's gate was not re-run for that revision. **Superseded in v2:**
  it was re-run in full at the new base `7d56694` — see Step 4 — so no Dion figure in
  this file is carried forward any longer.
- The egress block is verified against the request shapes the regression cell drives
  (remote `<link>`, `<img>`, `fetch()`, `WebSocket`) plus a wider one-off probe
  (`<script src>`, `@font-face`, `<iframe>`, `sendBeacon`, `<a ping>`, `EventSource`,
  `XMLHttpRequest` — 20 requests, all blocked). It is **not** a proof of no egress:
  UDP-based paths such as WebRTC/STUN are untested, and DNS resolution behaviour under
  the proxy was not measured. Those are named in the beaconfix report as residual
  rather than claimed closed.
