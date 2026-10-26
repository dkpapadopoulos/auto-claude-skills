## MODIFIED Requirements

### Requirement: Manifest parsing

The script SHALL treat as manifest entries every line of the form
`- Create:|Modify:|Test:|Delete:|Allow: `path``, SHALL strip trailing
`:N[-M]` line ranges, SHALL normalize a trailing-`/` directory entry to
`dir/*` so it covers contained files, and SHALL match changed files by exact
path or bash case-glob. A built-in meta allowlist (`docs/plans/*`,
`docs/superpowers/*`, `openspec/*`, `CHANGELOG.md`) and the plan file itself
SHALL always be covered. A meta allowlist pattern SHALL match nested paths
(for example `openspec/changes/<x>/proposal.md`) regardless of which files or
directories exist in the working directory: the patterns are matched as
patterns and never expanded against the filesystem first.
[Provenance: superpowers writing-plans SKILL.md task template (Files block
format, installed 6.1.1); Allow: is this change's extension; dir-entry
normalization and plan self-exemption added during implementation/review.
`docs/superpowers/*` added by superpowers-701-alignment: superpowers 7.0.1
writes design docs and plans there by default. The nested-path clause records
a defect found by the same change: the allowlist loop expanded each pattern
against the CWD, so with an `openspec/` directory present `openspec/*` became
the directory names and nested files reported as violations.]

#### Scenario: line-range stripping

- GIVEN a manifest entry `` `src/x.py:123-145` ``
- WHEN parsed
- THEN the entry used for matching is `src/x.py`

#### Scenario: Allow glob

- GIVEN `` - Allow: `tests/*` `` and a new untracked file `tests/t.sh`
- WHEN the script runs
- THEN `tests/t.sh` is covered

#### Scenario: superpowers' default doc location is meta

- GIVEN a plan saved at `docs/superpowers/plans/<date>-<slug>.md` that declares only the product files it changes, and a branch that also adds `docs/superpowers/specs/<date>-<slug>-design.md` and another plan under `docs/superpowers/plans/`
- WHEN the script runs
- THEN the verdict is clean (exit 0)
- AND a changed file under `docs/` but outside `docs/superpowers/` and `docs/plans/` is still listed as a violation (exit 1)

#### Scenario: nested meta paths are covered whatever exists on disk

- GIVEN a repository whose working directory contains an `openspec/` directory, and a branch that adds `openspec/changes/<x>/proposal.md` and `openspec/changes/<x>/specs/<cap>/spec.md`
- WHEN the script runs with a plan that declares only the product files it changes
- THEN the verdict is clean (exit 0)
