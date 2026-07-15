# Design: verify-and-record

## Capabilities Affected

- `project-verification` (extended — Step 3 writer becomes deterministic when
  `.verify.yml` exists)

## Architecture

One executable, `scripts/verify-and-record.sh` (Bash 3.2), invoked by the
model during the project-verification skill:

1. Refuses to guess: requires `.verify.yml` with `substrate: local`
   (any other substrate is an error, mirroring the skill contract).
2. Runs each `name:`/`run:` pair from the repo root, stdin `</dev/null`
   (suite-hang gotcha), capturing exit codes: 0 → `passed`, 127 →
   `could_not_verify`, other → `failed`.
3. Runs `gate-gaming-check.sh` resolved from the PLUGIN root (script-dir
   fallback), not the target repo — the script must work when verifying
   arbitrary repos that don't vendor the checker. Empty output →
   `gate_gaming_status: unverified` + `could_not_verify` entry (skill
   contract).
4. Writes the verdict JSON via `jq -n` from its measured values only, to
   `~/.claude/.skill-project-verified-<token>` (token from the singleton —
   same namespace as before), with `sha` = HEAD and a `writer` field for
   provenance.

## Decisions

- **Location `scripts/`**, not `hooks/lib/`: it is an executable command, not
  a sourceable lib; the canary source-probe would execute it. Routing
  governance not covering `scripts/` is acceptable because the writer is not
  an enforcement component (see Out-of-Scope).
- **Exit code**: 0 when the verdict was written (even a FAILING verdict — the
  script succeeded at recording), non-zero only when it could not measure or
  write. The model must never interpret exit 0 as "gates passed"; it reads
  the printed verdict summary.
- **`writer` field** is provenance metadata only — the guard does not read
  it, and it must never become an enforcement input (a forger would just set
  it).
- **`CLAUDE_PLUGIN_ROOT`-controlled checker resolution** is part of the same
  shell-trust model as `.verify.yml` itself: anyone who can set env or write
  the YAML already controls the shell and could write the artifact directly —
  no new forgery surface (governance review 2026-07-15).
- **Gate-gaming diff base** reuses `verdict.sh::_routing_base`
  (mainline-first): an `@{u}`-first base under-scopes the check on pushed
  branches, and a base or diff that cannot be resolved is `unverified`, never
  `clean` — only a diff that was actually computed reaches the checker.
- Classifier evidence is n=1 (2026-07-15 pilot); if future classifier
  versions flag the script invocation, the fallback is the documented
  per-instance user approval — no laundering.

## Out-of-Scope

- Any enforcement-side change: `openspec-guard.sh`, `verdict.sh`, and the
  gate predicates are untouched; the artifact's trust model is unchanged
  (CI remains the boundary).
- Canary/`_GATE_ENFORCE_LIBS` membership — the writer's loss fails toward
  deny, not open (proposal has the full argument).
- Non-`.verify.yml` discovery rungs; multi-substrate support.
- Coverage-adequacy integration (stays `unverified` pending an lcov artifact
  for bash suites).

## Acceptance Scenarios

Provenance: skill contract in `skills/project-verification/SKILL.md`;
classifier behavior from the 2026-07-15 pilot (memory:
`verdict-artifact-write-needs-user-approval`).

- WHEN the declared gate fails THEN the verdict records the command name in
  `failed[]` and the artifact is not clean (red fixture).
- WHEN the declared gate passes and gate-gaming-check returns clean THEN the
  verdict records `passed[]`, empty `failed[]`, `gate_gaming_status: clean`,
  and `sha` equal to the target repo's HEAD.
- WHEN a declared command's runner is missing (exit 127) THEN the name lands
  in `could_not_verify[]`, never silently in `passed[]`.
- WHEN `.verify.yml` is absent or declares a non-local substrate THEN the
  script exits non-zero without writing any verdict.
