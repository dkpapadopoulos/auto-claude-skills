# Design: shadow-corpus adjudication (Stage C2)

## Architecture

One bash-3.2 script, `scripts/shadow-adjudicate.sh`, in the posture
`gate-status.sh` established: purely observational with respect to the gate,
never sourced by `hooks/openspec-guard.sh`, deliberately EXCLUDED from
`_GATE_ENFORCE_LIBS`, and it writes no gate state.

```
~/.claude/.push-implement-shadow.jsonl        (C1, read-only here)
                 │
                 ▼
      scripts/shadow-adjudicate.sh  ──►  ~/.claude/.push-implement-adjudication.jsonl
                 │                                    (C2, append-only sidecar)
                 ▼
            --status readout
```

**Sidecar, not in-place.** Adjudications never mutate the shadow log. Its record
shape is frozen for readers, and an in-place rewrite of an append-only diagnostic
log is a data-loss surface for no benefit. This mirrors the
`.skill-invocation-evidence-sha-<token>` decision: a sidecar precisely because the
primary format has committed consumers.

`IMPLEMENT_ADJUDICATION_LOG` overrides the sidecar path, mirroring C1's
`IMPLEMENT_SHADOW_LOG`, so tests never touch the real corpus. The sidecar is
created `0600` before its first write and is NOT rotated — same reasoning as C1:
rotation would orphan adjudications, and the accumulation rate does not require it.

Never reads stdin. The suite runs under `< /dev/null` by convention, and an
interactive prompt loop would be both untestable there and a fresh way for the
script to hang a hook-adjacent path.

## Components

**`--next`** resolves the oldest v2 record with no adjudication in the sidecar and
prints its facts (`repo`, `branch`, `action`, `diff_base`, and the
`impl_in_chain`/`material_source`/`impl_evidence_kind` triple that made the leg
fire), its `transcript_path`, and the exact labeling command. It exists because
the realistic failure is not wrong code — it is that nobody runs the tool and the
corpus is never labeled.

**The labeling command** appends one adjudication object and prints what it
recorded. Adjudicating a `predicate_version` 1 record is REFUSED with an
explanation rather than silently accepted — v1 measured a different subject for
merges and pooling it would corrupt the rate at the source.

**`--status`** is the readout: episode count, every exclusion broken out, the
rate with its interval, the band, distance to the floor, and the horizon.

## Data flow: records → episodes → rate

1. **Filter** to `predicate_version == 2`. v1 counted and reported separately.
2. **Group** into episodes by `(repo, branch, session_token)`, with membership
   bounded to 30 minutes from the episode's FIRST record — anchored, not rolling.
   A rolling inter-record gap would chain a whole day of intermittent pushes into
   one episode and push the denominator below the real number of decision points.
3. **Resolve each episode's verdict — worst-verdict-wins.** Any `false_block`
   among an episode's records makes the episode a false block; otherwise any
   `unknown` makes it unknown; otherwise `true_catch`. Deny-bias, consistent with
   how the verdict layer already breaks ties, and it biases *against* flipping the
   gate. Accepted cost: one bad record poisons an otherwise-clean episode.
4. **Exclude** three populations from the headline rate, each reported alongside
   rather than silently dropped: `unknown` episodes, agent-claimed episodes, and
   v1 records.
5. **Compute** the one-sided 95% Clopper–Pearson interval and the band.

**Bands** (from `implement-shadow-event/design.md`, unchanged here):

| band | condition | computed as |
|---|---|---|
| DENY | upper bound < 10% | `P(X ≤ k \| n, 0.10) < 0.05` |
| ADVISORY-ONLY | lower bound ≥ 20% | `P(X ≥ k \| n, 0.20) ≤ 0.05` |
| NARROWED | neither of the above | — |

**No interval inversion is needed.** The binomial CDF is monotone in `p`, so
"upper bound < 0.10" is equivalent to evaluating the CDF once at `p = 0.10`, and
likewise for the lower bound at `p = 0.20`. This matters for bash 3.2: a direct
CDF evaluation is a single `awk` loop over `k+1` terms, whereas inverting for the
bound would need bisection. The two forms are mathematically identical — this is
exact Clopper–Pearson, not an approximation of it.

Wilson MUST NOT be substituted. It is anti-conservative in the tail and disagrees
at real boundaries (it calls 8/23 ADVISORY-ONLY where exact says NARROWED), which
is why that case is a pinned test.

**Floor gate.** Below n=29 rate-bearing episodes, or fewer than 2 distinct repos,
`--status` MUST print `insufficient data` in place of a rate. A point estimate
over 3 episodes is not a low rate, it is an unmeasured one, and printing one
invites exactly the misreading the floor exists to prevent.

The floor is applied to the rate's own denominator (`true_catch + false_block`),
NOT to the count of adjudicated episodes. `unknown` episodes are adjudicated but
excluded from the headline rate, so gating on the labelled count would let 29
labelled episodes of which 15 were `unknown` print a band computed over n=14 —
below the pre-registered floor.

**Worst-case bound.** Alongside the headline rate, `--status` prints the rate
recomputed with every `unknown` counted as a `false_block`, so the gate cannot be
cleared by leaving hard cases unlabeled.

## Claimant detection

`claimant: "agent"` when EITHER `CLAUDECODE` is set OR the parent process is
`claude`. Both were measured present inside a Claude Code Bash call; a human at a
terminal trips neither.

**A tty check was specified and then removed during implementation.** It was
caught by its own test: `[ ! -t 1 ]` fires whenever stdout is redirected, so every
adjudication made from a script, a pipe, or `> file` was recorded as
agent-claimed. Because human-claimed episodes are the only ones that count, that
is not a cosmetic false positive — it makes the n=29 floor unreachable for anyone
who pipes output, silently. And it buys nothing: the two remaining signals are
direct evidence of an agent context, whereas tty is a proxy, and all of them are
forgeable regardless.

Agent-claimed adjudications are recorded in full and EXCLUDED from the headline
rate until re-confirmed by a human-claimed adjudication of the same record.

The bias is deliberate and one-directional: a human using `!` inside a session is
misclassified as agent, costing a re-confirmation. The reverse error — an
agent's self-label silently counted — is the one that corrupts the rate.

`CLAUDE_CODE_SESSION_ID` is checked alongside `CLAUDECODE` — it is the repo's
established "inside a Claude Code turn" marker (`session-token.sh`,
`phase-attest.sh`, `verify-and-record.sh`, `gate-status.sh`).

**The `claude`-parent signal is inert in this harness.** A Claude Code Bash call
runs the script under an intermediate shell, so `ps -o comm= -p $PPID` reports
`/bin/zsh` and `claude` is only the grandparent. It is kept because it costs
nothing and catches a direct-parent case, but it carries no weight in practice.
Walking several ancestors *would* fire — and ancestry survives `env -u`, so it
genuinely hardens the bypass below — but it was tried and reverted: inside any
Claude Code session every ancestry contains `claude`, which makes the human path
unreachable in-session and untestable. Buying marginal hardening by making the
only countable claimant untestable is the wrong trade.

**Honest bound on what this buys.** Every signal is forgeable, and the bypass is
one token:

```
env -u CLAUDECODE -u CLAUDE_CODE_SESSION_ID shadow-adjudicate.sh <id> --verdict true_catch --reason x
→ recorded: <id>  true_catch  (human-claimed)
```

The resulting provenance is indistinguishable from a human piping from a zsh
script, so the audit trail cannot catch it after the fact either. This model is
therefore sound against the *realistic* failure — an agent working through
`--next` and labelling as it goes, self-grading without noticing — and is not a
control against a motivated bypass. That is an acceptable trade for a diagnostic
whose output is advisory, but it must not be described as more than it is. The
output labels results **human-claimed, never human-verified**, which is the
accurate framing.

## Error handling

Missing shadow log, empty corpus, missing `jq`, unwritable sidecar, malformed
record: report and exit non-zero for genuine CLI misuse (bad verdict, unknown
record id), exit 0 with an explanatory readout for "nothing to do" states. The
script is a developer tool, not a hook — it does not need fail-open semantics,
but it MUST NOT be reachable from a gate path where an exit code could matter.

## Testing

`tests/test-shadow-adjudicate.sh`, against a synthetic fixture corpus written to a
temp `IMPLEMENT_ADJUDICATION_LOG`/`IMPLEMENT_SHADOW_LOG`. The real v2 corpus is
empty, so fixtures are the only option — and per the fixture-repo precedent,
diff-dependent assertions need a harness-built corpus anyway.

- Episode dedup collapses the real v1 shape (11 records, one repo+branch, 9-min
  window) to exactly 1 episode. The regression that matters most.
- Worst-verdict-wins: an episode with `true_catch` + `false_block` resolves false.
- Agent-claimed excluded from the rate; a later human-claimed adjudication of the
  same record re-includes it.
- `unknown` excluded from headline, present in the worst-case bound.
- Band boundaries under **exact Clopper–Pearson**: 0/29 → DENY and 0/28 → NOT
  DENY (pins the floor); 9/23 → ADVISORY-ONLY; 8/23 → NARROWED; 5/23 → NARROWED.
  The 8/23 case is load-bearing: Wilson would call it ADVISORY-ONLY and exact does
  not, so it pins that the implementation is exact rather than an approximation.
- Floor: 30 episodes in 1 repo fails diversity; 30 across 2 repos passes and
  prints a rate, band, and worst-case line. The above-floor branch is exercised
  end-to-end — 0/30 → DENY, 15/29 → ADVISORY-ONLY, and 30 clean + 5 unknown →
  headline `0/30` with worst case `5/35` → NARROWED, which is the clause that
  stops the gate being cleared by leaving hard cases unlabelled.
- Floor binds on the rate's denominator: 14 rate-bearing + 20 unknown (34
  labelled) stays below the floor.
- An EMPTY field must not drop a record: `IFS=$'\t' read` collapses consecutive
  tabs, so a record with an empty `branch` — which `implement-shadow.sh` writes
  whenever `git rev-parse --abbrev-ref HEAD` fails — silently vanished from the
  denominator. Fixtures cover empty `branch` and empty `session_token`, plus
  `--next` rendering.
- One unparseable JSON line must not truncate the corpus, and must be reported.
- A record with a null/missing `ts` is excluded AND counted.
- A truncated command line (`--verdict` with no value) exits non-zero rather than
  looping forever; bounded by `ulimit -t` so a regression fails fast.
- v1 record refused with a non-zero exit.
- Bash 3.2: `/bin/bash -n` clean and exercised under `/bin/bash`.

## Trade-offs

- **`--status` computes a rate at all.** This is the "polished rate for the wrong
  population" Codex warned about. Mitigated by the floor gate (no rate below n=29
  / 2 repos), by every exclusion being printed, and by the readout being
  explicitly non-authoritative.
- **Worst-verdict-wins is lossy.** Majority-wins would be more faithful to what an
  episode "was". Chosen anyway: the asymmetry of harm favors over-counting false
  blocks, since the consequence is a gate that stays advisory longer.
- **30 minutes is a judgment call.** It is not calibrated — it is chosen to
  comfortably span the observed 9-minute retry burst. If real episodes are later
  observed straddling it, the window is the thing to revisit, and changing it
  changes the denominator, so it is recorded here rather than left implicit.
  `session_token` + `branch` already carry most of the correlation signal; the
  window is a secondary guard against a single long session being counted once.
- **Repo identity is the `repo` field verbatim.** Two clones of the same project
  at different paths would satisfy the ≥2-repo diversity requirement while being
  substantively the same codebase. Accepted rather than normalized: remote-URL
  resolution adds a git call per record and a failure mode, for an edge case that
  a reviewer reading the `--status` repo list will notice immediately. The repo
  list is therefore printed, not just counted.

## Dissenting views

- **Codex (accepted at C1, still live):** "C2/C3 are not worth building as
  proposed — they will produce a polished rate for the wrong population." C1
  retargeted the population from `deny:*` records to shadow events, which
  addresses the "wrong population" half. The "polished rate" half is answered by
  the floor gate, not dismissed.
- **Unresolved (inherited):** whether `<10%` is the right threshold at all. This
  change only makes it computable. Revisit once ~10 real episodes exist.

## Decisions

1. Sidecar file, never mutating the C1 log.
2. Worst-verdict-wins per episode (deny-bias), user-confirmed.
3. Agent-claimed segregated from the rate rather than merely annotated.
4. Floor gate suppresses the rate entirely below n=29 / 2 repos.
5. Non-interactive; `--next` carries the ergonomics instead.
6. The deny-flip, the leg, and the C3 consumer stay out of scope.

## Out-of-Scope

- Any change to a `permissionDecision`, the IMPLEMENT leg, or its predicate.
- The deny-flip itself and the C3 backtest consumer.
- Changing the `<10%` threshold, the bands, the floor, or the horizon — those are
  pre-registered in `implement-shadow-event/design.md` and are inputs here.
- Retroactive adjudication of the v1 corpus.
