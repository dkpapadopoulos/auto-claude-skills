# Design: Installed-Plugin Drift Canary

## Architecture

One new block in `hooks/session-start-hook.sh`, placed immediately after the
F5 push-gate precondition canary (Step 6a-bis), before preset resolution. It
appends at most **one** combined warning to `WARNINGS`.

### Activation condition (all must hold, else silent skip)

1. Session cwd is the plugin's **source repo**: `<cwd>/.claude-plugin/plugin.json`
   exists and its `.name` equals the running plugin's name read from
   `${PLUGIN_ROOT}/.claude-plugin/plugin.json`. cwd comes from the hook
   payload's `.cwd` field, falling back to `$PWD`.
2. `PLUGIN_ROOT` is not the source repo itself (canonical-path compare via
   `cd && pwd`) — running from source means no drift is possible.
3. Both manifests readable and jq available — any missing/unparseable input →
   silent skip (fail-open; a canary error must never break session start).

### Check 1 — version drift

String-compare `.version` between the cache manifest and the source manifest.
Any inequality is drift (no semver ordering, no commits-behind). Message names
both versions and the remedy (restart/reinstall).

### Check 2 — enforcement-manifest drift

`cksum` over the exact gate-enforcement file list the F5 canary owns:
`hooks/openspec-guard.sh`, `hooks/lib/branch-ledger.sh`,
`hooks/lib/verdict.sh`, `hooks/lib/git-command.sh`,
`hooks/lib/session-token.sh` — cache vs source. Any differing or one-sided
missing file → drift, naming the files. This catches enforcement drift
**without** a version bump (unreleased or uncommitted gate edits).

PAIRED: this list mirrors the F5 canary list; a new gate-enforcement lib must
be added to both in the same change.

### Output

A single `PLUGIN DRIFT CANARY: …` warning combining whichever checks fired,
appended to `WARNINGS` with the same `|| WARNINGS="[]"` self-healing pattern
as F5.

## Trade-offs

- **cksum vs shasum**: cksum is POSIX, fastest, and drift detection is not a
  security boundary — collisions are irrelevant here.
- **Version string-compare vs semver ordering**: "differs" is the honest
  claim; direction adds parsing cost and no actionable difference.
- **Warning-only vs deny**: deny would brick sessions on every source edit;
  the canary's job is visibility, the push gate remains the enforcement point.

## Out of Scope

- commits-behind metrics, auto-reinstall/remediation, checking non-gate files,
  any deny behavior, jq-less fallback coverage.

## Decisions

- Placement after F5 keeps all session-start canaries adjacent and shares the
  `WARNINGS` machinery.
- Bash 3.2 compatible; no associative arrays; unquoted arithmetic only on
  validated-numeric input (none needed here).

## Implementation Notes (synced at ship time)

Behavior ships exactly as specified; three review-driven internal refinements:

- The gate-file list is now a shared `_GATE_ENFORCE_LIBS` variable defined in
  the F5 canary block and reused by the drift canary — the PAIRED-lists
  discipline became structural (single point of extension) instead of
  comment-enforced.
- `.cwd` is extracted in the existing Step-1c payload-parsing block alongside
  `session_id`/`transcript_path`, so the drift canary adds no unconditional jq
  fork of its own.
- The warning append uses `_W_NEW="$(…)" && WARNINGS="${_W_NEW}"` rather than
  the F5 block's `|| WARNINGS="[]"` reset, because at this point WARNINGS may
  already hold an F5 warning that a jq failure must not discard.
- Test hardening: silent cases (b)/(e) also assert `SessionStart` presence so
  they cannot pass vacuously on a crashed hook (13 assertions, was 11).
