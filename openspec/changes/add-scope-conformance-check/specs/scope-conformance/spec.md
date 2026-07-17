# scope-conformance Specification

## ADDED Requirements

### Requirement: Deterministic tri-state scope verdict

`scripts/scope-conformance.sh <plan-file> [<base-ref>]` SHALL compare the
branch's changed files (committed + uncommitted + untracked, vs the resolved
base) against the scope declared in the plan file and SHALL exit 0 with a
clean verdict, 1 with a violation verdict listing each uncovered file, or 2
with an unverified verdict. It SHALL NOT require jq or Node and SHALL run
under macOS /bin/bash 3.2.
[Provenance: adapted from worklease src/conformance.js respected/violation/
warning partition; tri-state and fail-open shape per repo doctrine CLAUDE.md
"enforceable done-gate is owned and deterministic" + advisory-stays.]

#### Scenario: clean branch

- GIVEN a plan whose `**Files:**` entries cover every changed file
- WHEN the script runs
- THEN it exits 0 and prints `scope-conformance: clean`

#### Scenario: out-of-scope change (including deletes)

- GIVEN a branch change (edit or delete) to a file no manifest entry covers
- WHEN the script runs
- THEN it exits 1 and lists that file under a violation verdict

#### Scenario: missing manifest degrades safely

- GIVEN a missing, unreadable, or entry-less plan file
- WHEN the script runs
- THEN it exits 2 with `unverified` — never a false `clean`, never a block

### Requirement: Manifest parsing

The script SHALL treat as manifest entries every line of the form
`- Create:|Modify:|Test:|Delete:|Allow: `path``, SHALL strip trailing
`:N[-M]` line ranges, and SHALL match changed files by exact path or bash
case-glob. A built-in meta allowlist (`docs/plans/*`, `openspec/*`,
`CHANGELOG.md`) SHALL always be covered.
[Provenance: superpowers writing-plans SKILL.md task template (Files block
format, installed 6.1.1); Allow: is this change's extension.]

#### Scenario: line-range stripping

- GIVEN a manifest entry `` `src/x.py:123-145` ``
- WHEN parsed
- THEN the entry used for matching is `src/x.py`

#### Scenario: Allow glob

- GIVEN `` - Allow: `tests/*` `` and a new untracked file `tests/t.sh`
- WHEN the script runs
- THEN `tests/t.sh` is covered
