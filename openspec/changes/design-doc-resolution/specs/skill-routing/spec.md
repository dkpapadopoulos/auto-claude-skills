# skill-routing delta: design-doc resolution

## ADDED Requirements

### Requirement: A change's design doc is resolved read-only, with four outcomes

`scripts/resolve-design-doc.sh [--slug <change-slug>]` SHALL report where a change's design doc is, as one tab-separated line `<outcome> <source> <path> <count>` with outcome one of `resolved`, `stale`, `ambiguous`, `absent`. It MUST check, in order: the path recorded in session state for the slug; `openspec/changes/<slug>/design.md`; `docs/plans/YYYY-MM-DD-<slug>-design.md`. A recorded path MUST be checked for readability and reported `stale` when unreadable, and MUST NOT be replaced by any other file: not by a filename match, and not by a file of the same basename elsewhere, `docs/plans/archive/` included. The slug MUST be compared as a fixed string. The script MUST NOT derive a slug from a branch name, MUST NOT write session state, and MUST NOT create, move or delete any file. When a state file exists and is not exactly one JSON object of the expected shape (`changes` an object, each entry an object, a `design_path` a string without tab or newline, or null), or `jq` is missing while one exists, it MUST exit 3 and print no outcome line, with and without `--slug`, so "could not check" is never read as `absent` or as "nothing recorded".

#### Scenario: a recorded, readable path resolves from state

- **GIVEN** session state records `design_path` for change `f` and that file is readable
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `resolved`, source `state`, that path, count 1

#### Scenario: a recorded path that is gone is stale, not replaced

- **GIVEN** session state records a `design_path` whose file does not exist
- **AND** a different `docs/plans/2026-01-01-f-design.md` exists
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `stale`, source `state`, the recorded path, count 0

#### Scenario: a same-named file in the archive does not stand in for a recorded doc

- **GIVEN** session state records `docs/plans/2026-01-01-f-design.md`, `openspec/changes/f/design.md` or a path outside the repository, and that file does not exist
- **AND** a file of the same basename exists under `docs/plans/archive/`
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `stale`, source `state`, the recorded path, count 0

#### Scenario: nothing recorded, one file matches by name

- **GIVEN** no recorded path and exactly one `docs/plans/YYYY-MM-DD-f-design.md`
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `resolved`, source `docs-plans`, that path, count 1

#### Scenario: several files match by name

- **GIVEN** no recorded path and two `docs/plans/YYYY-MM-DD-f-design.md` files
- **WHEN** the script runs with `--slug f`
- **THEN** it prints `ambiguous`, source `docs-plans`, an empty path, count 2, followed by both candidates

#### Scenario: a slug matches only itself

- **GIVEN** `docs/plans/2026-01-01-auth-design.md` and `docs/plans/2026-01-01-auth-tokens-design.md`
- **WHEN** the script runs with `--slug auth`, then `--slug tokens`, then a slug holding `*`, `.`, `?` or `[`
- **THEN** `auth` resolves to the first file only, `tokens` is `absent`, and the metacharacter slug is `absent` with exit 0

#### Scenario: no slug means only the recorded arm

- **GIVEN** no `--slug`
- **WHEN** session state has one open change with a design path, two, or none
- **THEN** the outcome is that path's, `ambiguous` from `state`, or `absent`; filenames are not searched

#### Scenario: an unreadable state file is "could not check"

- **GIVEN** a state file for this session that is not one JSON object, whose `changes` is not an object, whose `design_path` is a number, a boolean, an array or holds a tab or newline, or `jq` is not on PATH while a state file exists
- **WHEN** the script runs, with or without `--slug`
- **THEN** it exits 3, prints nothing on stdout, and says "cannot check" on stderr

#### Scenario: it writes nothing

- **WHEN** the script runs in any of the cases above
- **THEN** the session state file and every file under the repository are byte-identical before and after

### Requirement: Readers of a design doc say what they found

`openspec-ship` and `deploy-gate`'s design-intent check MUST call `scripts/resolve-design-doc.sh` by its `<PLUGIN_ROOT>` path, passing the change slug, and MUST NOT skip silently on any outcome. `openspec-ship` MUST make the call in Step 3, before it creates or moves anything, and MUST use that kept outcome in its Divergences step without calling again, because its own Steps 3, 6 and 7b create and move the files the script looks for. Every outcome other than `resolved` MUST end with shipping continuing; none may leave the step waiting. A doc resolved by filename (source `openspec` or `docs-plans`) MUST be labelled as found by filename in the Divergences report and MUST NOT be moved. `openspec-ship`'s archive step MUST keep moving only paths recorded in session state. On `ambiguous` or `stale` the Divergences step MUST ask the user which file is the design doc and MUST NOT choose one; a file the user names is used and labelled as the user's choice, and with no answer the step says no report was written. `deploy-gate` MUST NOT invent a slug from the branch name, and MUST say that `absent` without a slug means only that nothing was recorded. Exit 3 MUST be reported as "could not check", distinct from `absent`. In `deploy-gate`, `stale` is a soft warning and `absent` or `ambiguous` are informational.

#### Scenario: the Divergences step names every outcome

- **WHEN** `skills/openspec-ship/SKILL.md` is read
- **THEN** Step 3 calls `'<PLUGIN_ROOT>/scripts/resolve-design-doc.sh'` with `--slug`, before its pre-flight check and before Step 6, and that is the only call in the file
- **AND** Step 7c uses the outcome Step 3 kept, names `resolved`, `stale`, `ambiguous`, `absent` and exit 3, and points at `references/design-doc-outcomes.md`
- **AND** that reference has a row for each outcome, says where each source's doc is by Step 7c, labels a filename match as found by filename and not moved, tells the reader to ask the user on `ambiguous` and on `stale` and what to do with and without an answer, and ends `absent`, `ambiguous`, `stale` and exit 3 with shipping continuing

#### Scenario: the archive step is not widened

- **WHEN** `skills/openspec-ship/SKILL.md` Step 7b is read
- **THEN** it moves the four recorded paths and does not call the resolver

#### Scenario: deploy-gate grades the outcome

- **WHEN** `skills/deploy-gate/SKILL.md` check 4 is read
- **THEN** it calls the resolver, warns on `stale`, passes `resolved`, treats `absent` and `ambiguous` as informational, and reports exit 3 as "could not check"
- **AND** it says not to make a slug up from the branch name, and that without `--slug` `absent` means only that nothing was recorded

## MODIFIED Requirements

### Requirement: Spec-driven preset is announced once per session and rewrites no hint

The plugin MUST support a `spec-driven` preset whose `openspec_first` flag, when `true`, makes `openspec/changes/<feature>/` the place design intent is persisted instead of `docs/plans/`. The preset is carried by a once-per-session notice from the session-start hook and by the skills that read it (`design-debate` writes its output there; `openspec-ship` syncs an existing change instead of creating one). It MUST NOT be carried by rewriting phase composition hints, and no per-prompt text redirects an ordinary DESIGN or PLAN step. The notice MUST state where design intent belongs and that this was not verified; it MUST NOT state that design intent has been persisted or committed, because the hook checks neither, and it MUST NOT be worded as an instruction.

#### Scenario: spec-driven preset active announces the mode and rewrites no hint
- **GIVEN** `~/.claude/skill-config.json` contains `{"preset": "spec-driven"}`
- **WHEN** session-start hook runs
- **THEN** its output MUST contain "spec-driven preset active: design intent belongs in openspec/changes/<feature>/; not verified this session"
- **AND** its output MUST NOT contain "design intent persisted to openspec/changes/"
- **AND** the cached registry's `phase_compositions.DESIGN.hints` and `phase_compositions.PLAN.hints` MUST be empty
