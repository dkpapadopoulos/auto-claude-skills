## PR Review: publish-guard.sh exit-trap ordering + jq-deny fallback + canary extension

## Summary

Two related fixes in `publish-guard.sh` (#187: EXIT trap leak and silent jq-failure allow on confirmed leak) plus a gap-fill in `session-start-hook.sh` adding `scripts/memory-leak-check.sh` to the F5 push-gate canary and drift-canary manifest. No skill changes. Both hook changes are narrowly scoped, well-commented, and correctly handle the CLAUDE.md invariants. **Mergeable.**

---

## What passes ✅

- **No `set -e`** introduced in either hook. `publish-guard.sh` retains `trap 'exit 0' ERR`; `session-start-hook.sh` is unchanged on that front.
- **Bash 3.2 compatibility**: no `declare -A`, no `${array[n]}` subscripts, no bash 4+ constructs. The `:-` parameter guards in the EXIT trap body are 3.2 safe.
- **EXIT trap ordering** (`publish-guard.sh:97–99`): the unified trap is armed before any `mktemp` call, with `${MLC_CORPUS_CACHE:-}` and `${_TMP:-}` guards, so firing before assignment is a no-op. Correctly closes the window where the ERR trap could fire mid-setup and leave `pg-corpus.*` on disk.
- **`&&` in EXIT trap body is safe**: both conditional `rm` arms use `&&` (which suppresses the ERR trap on a false left side per POSIX) and the final `:` ensures the trap body exits 0, avoiding any residual ERR-trap interaction.
- **`MLC_CORPUS_CACHE` lifetime**: created with `|| MLC_CORPUS_CACHE=""` fallback so a mktemp failure doesn't trip the ERR trap; exported for child `/bin/bash "${_ENGINE}"` calls; cleaned up by the EXIT trap including the `.tmp` variant (`publish-guard.sh:101–104`).
- **jq deny fallback** (`publish-guard.sh:213–224`): the `if ! jq ... 2>/dev/null; then` guard correctly wraps the deny emission. The `printf` fallback uses a fixed literal — no `${_MSG}` interpolation — so a model-authored citation string cannot produce unparseable JSON and silently allow. Detail is sent to stderr. Both paths reach `exit 0`.
- **Fixed literal is valid JSON**: the fallback string at `publish-guard.sh:220–221` parses cleanly (`#174`, `<file>`, `<line>`, angle brackets are all valid JSON string content).
- **`permissionDecisionReason` present in both paths**: consistent with #254 requirement that the agent-visible field carries the remediation text.
- **session-start canary** (`session-start-hook.sh:641–644`): `memory-leak-check.sh` is parse-checked with `bash -n`, not source-probed — correct, matching the treatment `publish-guard.sh` already receives and explained by the comment.
- **Drift manifest** (`session-start-hook.sh:702`): `scripts/memory-leak-check.sh` added alongside `publish-guard.sh` in `_DRIFT_FILES` loop. Consistent with the PAIRED requirement: the canary list and drift list are extended together.
- **Fail-open preserved**: canary additions only append to `_CANARY_BAD` (warning path), never block session start.
- **No hardcoded secrets, tokens, or private hostnames.**
- **kebab-case**: no new files or directories introduced.

---

## Blocking issues 🚫

None found.

---

## Recommendations 💡

- The `_MEMPROBE` probe at `publish-guard.sh:106` now runs with `MLC_CORPUS_CACHE` exported to an empty file. If the engine treats an existing-but-empty cache as "already built with zero shingles" rather than "needs rebuild", the subsequent `_check` calls would all pass against an empty shingle set and silently allow leaks. This is an engine contract question, not a hook bug, but worth verifying in `scripts/memory-leak-check.sh`'s cache-staleness logic (the comment says "rebuilds whenever any corpus file is newer" — confirm the empty-file case triggers a rebuild rather than a cache hit).
