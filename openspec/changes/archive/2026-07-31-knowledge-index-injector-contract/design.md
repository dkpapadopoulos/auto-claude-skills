# Design: knowledge-index-injector-contract

## Architecture

The committed-knowledge tier is a three-stage pipeline:

```
knowledge-rebuild-index.sh   →   .claude/knowledge/index.md   →   session-start-hook.sh
   (producer)                        (artifact)                      (consumer, grep -E '^- \[')
                                          ↑
                              knowledge-validate.sh (gate)
```

The gate sat beside the artifact, not in front of the consumer, and asserted a weaker property than delivery. The fix moves the gate onto the consumer's contract:

```sh
INJECTABLE="$(grep -E '^- \[' "${DIR}/index.md" 2>/dev/null)"
for slug in ${SLUGS}; do
    printf '%s\n' "${INJECTABLE}" | grep -qF "(${slug}.md)" || _err ...
done
```

Composition, not duplication of the predicate as a regex over the slug: the slug stays a fixed string (`grep -qF`), so a name containing regex metacharacters cannot change the meaning of the check, and the `(slug.md)` bracketing prevents substring bleed between `foo` and `bar-foo` in both directions.

## Decisions & Trade-offs

**Compose the consumer's filter rather than re-implement it.** Re-deriving the predicate as `grep -qE "^- \[.*\(${slug}\.md\)"` would work but interpolates a filename into a pattern and states the contract twice. Filtering first and matching literally states it once.

**The predicate literal is still written in two files.** `^- \[` appears in both the hook and the validator; there is no shared bash lib on the session-start hot path worth adding for one token. That duplication is the residual gap, and it is closed by test, not by prose: `tests/test-knowledge.sh` extracts the literal from both files and asserts byte-equality, so drift from either side fails the suite. This is the compensating-layer pattern the new review question describes — legitimate because the root cause (a validator asserting the wrong property) is fixed, and the residual gap is named.

**Example-based test alone was insufficient.** The first regression proved only that one non-injectable shape (bold-wrapped) is rejected. If the hook's predicate were later *loosened*, the validator would silently become stricter than the injector and false-block legitimate bundles with every example assertion still green. The structural equality assertion covers both directions.

**Rejected: propagate the fix to `scripts/memory-validate.sh`.** It has the same loose predicate against `MEMORY.md`, but auto-memory is a Claude Code built-in and no hook of ours injects it, so there is no consumer predicate to match. Tightening it would invent a contract rather than enforce one.

**Rejected: importing claude-mem's merge rubric wholesale.** The rubric rejects on sight guards, fallbacks, retries, fail-open modes, watchdogs, truncation and new state files. Measured against this repo that would condemn 542 fail-open sites across 29 of 30 hook files — where fail-open is load-bearing, since a throwing hook breaks the user's editor loop — plus `branch-ledger.sh`, `verdict.sh` and both session-start canaries. Only the question transfers.

**Rejected on measurement: an annotated fail-open convention plus a detector for unannotated sites.** 0 of 4 documented defects in this repo would have been caught by it (the Bash-3.2 quoted-arithmetic abort, the ERR-trap + unguarded-source bypass, the zsh unmatched-glob fatal, the push-gate capture classifier bug — none is a grep-visible fail-open idiom), the retrofit is 542 sites, and a detector that labels rather than fixes is precisely what the rubric's own §1 rejects as "observability is not a fix". Recorded here so the reasoning is not re-litigated.

**The new review question is deliberately left inside the severity floor.** It produces a `quality`-category finding, which the floor demotes without an observable failure path. Rather than carve it out — reopening the nit accretion the floor exists to stop — the question requires the reviewer to name the input that still fails. A genuinely routed-around root cause can always name one; a speculative "this looks like a bridge" cannot. Residual limitation, accepted and not solved here: a structural finding needing precise concurrent timing (a race) may still lack a nameable single input and be floored — but that is the floor's pre-existing tradeoff for every quality finding, not one this change introduces.

## Dependencies

None. No new packages, APIs, or schema changes. Bash 3.2 compatible; the validator was executed under `/bin/bash` 3.2 and `dash` in addition to the suite's `bash`.
