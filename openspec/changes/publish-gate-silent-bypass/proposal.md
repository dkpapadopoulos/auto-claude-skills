# Proposal: the #174 leak gate must not fail silently

## Why

PR #185 shipped the #174 publication leak gate. A post-merge silent-failure
audit found **four defects that violate the gate's own stated contract**, two of
which let a real leak through with no signal at all. Each was reproduced against
the shipped code before any fix was written.

The contract (`hooks/publish-guard.sh:6-9`) is explicit: detection is
FAIL-CLOSED, and inability to check is FAIL-OPEN **and announced** — because a
silent allow is byte-indistinguishable from a clean check, so the author never
learns the gate did not run.

| # | Path | Contract | Actual |
|---|---|---|---|
| S2 | `--body "$(cat leaky.md)"` | announce | **silent allow** |
| S1 | corpus/body unreadable by awk | announce | **silent "clean"** |
| S4 | `CLAUDE_PLUGIN_ROOT` unset + bad `$0` | announce | **silent allow** |
| S3 | exemption partially unbuildable | announce | **false DENY** |
| S5 | unparseable hook input | announce | silent allow |
| S6 | engine `rc=1`, empty stdout | deny/announce | silent allow |
| S10 | deny co-occurring with cannot-check | both | deny only |

### S2 is the one that matters most

The whole-command scan sees only **literal** text. `--body "$(cat leaky.md)"`
reaches the hook as the *unexpanded* string, so no private words are present at
scan time, and because no body-file token appears, the structural backstop never
fires either. Result: a complete bypass with zero signal.

This is in-repo idiom, not an exotic shape — `improvement-miner/SKILL.md` itself
instructs `--title "$(cat /tmp/mine-title.txt)"`. The diagnostic tell was that
`--body-file <(…)` *announced* while `--body "$(…)"` said nothing: the backstop
was one token-class short.

### Why it shipped green

Every pre-existing "allowed" assertion is `assert_equals … "" "${out}"`, which
passes when the hook does nothing at all. Such an assertion structurally cannot
distinguish "checked and clean" from "never ran" — so S1 and S4 were invisible
to a green suite.

## What Changes

- `hooks/publish-guard.sh` — announce shell-expanded bodies (outside the
  zero-files branch); split the `_ROOT` assignment out of its ERR-trap hazard;
  announce unparseable input; treat a detail-less `rc=1` as cannot-check; fold a
  co-occurring cannot-check into the deny message.
- `scripts/memory-leak-check.sh` — `PIPESTATUS` on both shingling pipelines and
  on the exemption build; never truncate a partial exemption; reject a
  non-regular body **after** the corpus notices (the guard probes with
  `/dev/null`, a character device).
- Tests — ten new fixtures, each confirmed to fail against the real pre-fix code.

`hooks/lib/git-command.sh` is **unchanged**: its predicates were probed across
~20 `gh` shapes with no misclassification. The defects were in the guard and the
engine.

## Capabilities

- **Modified**: `pdlc-safety`

## Impact

The gate now announces where it previously stayed silent. Announcements are
advisory (`systemMessage`, no `permissionDecision`), so **no new deny path is
introduced** — except S3, which removes a false deny. Ordinary literal
publications remain silent; verified against the real 164-file corpus.

## Out of Scope

- S7 — unguarded `jq -n` on the deny emitter (hardening; the plausible trigger
  was tested and jq tolerates it).
- S8 — the ~2.1s hook cost from shingling the corpus three times per publish.
- S9 — adding `scripts/memory-leak-check.sh` to the session-start drift canary.

Tracked as a follow-up; deliberately excluded to keep a security fix tight and
independently verifiable.
