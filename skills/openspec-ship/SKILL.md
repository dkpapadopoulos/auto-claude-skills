---
name: openspec-ship
description: Use when shipping a completed feature and generating as-built OpenSpec docs before branch finalization
---

# OpenSpec Ship — Retrospective Change Documentation

Generate permanent "as-built" OpenSpec documentation from completed code, then archive it alongside Superpowers execution artifacts.

## When to Use

Invoke this skill during the SHIP phase after `verification-before-completion` passes and before `finishing-a-development-branch`. It runs automatically as part of the SHIP composition chain.

## When to Skip

Skip this skill ONLY when ALL of these are true:
- No Superpowers plan was executed in this session (no `docs/plans/` or `docs/superpowers/plans/` artifact)
- The session was debugging, reviewing, or non-feature work

**Scope and size are NOT skip criteria.** If a Superpowers plan was executed — regardless of how small the change — this skill MUST run. A 3-file config change that went through brainstorming → writing-plans → execution still needs as-built documentation.

If you are uncertain whether to skip, run it. The cost of an unnecessary openspec-ship is minutes; the cost of missing documentation is permanent knowledge loss.

## Hard Precondition

Before proceeding, verify that `verification-before-completion` has already run in this conversation. Look for fresh verification evidence appropriate to the project (e.g., test runner output, lint results, build confirmation — not all projects have all three). If no fresh verification evidence exists, STOP and inform the user:

> "openspec-ship requires passing verification. Invoking verification-before-completion first."

Then invoke `Skill(superpowers:verification-before-completion)` before continuing. Defer to `verification-before-completion` for the exact command set appropriate to the project.

## Session State

When this skill starts, populate the session state file with linkage information:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root.
3. Call `openspec_state_upsert_change "<token>" "<change_slug>" "<plan_path>" "<spec_path>" "<capability_slug>"`.
4. If the state file doesn't exist yet (verification-before-completion hasn't run), the helper creates it with `verification_seen: false`.

## Input

The user should provide:
- **Required for SP artifact archival:** `plan_path` — the path to the implementation plan (e.g., `docs/plans/2026-04-15-feature-plan.md`); also checks legacy `docs/superpowers/plans/`. If not provided, skip SP artifact archival with warning.
- **Optional:** `feature-name` — kebab-case change name. If not provided, derive from `plan_path` by stripping the date prefix (e.g., `2026-03-14-feature.md` → `feature`). If neither is available, ask the user.

## Steps

### Step 1: Detect Environment

**Primary:** Read the session's `OpenSpec:` capability line from the session-start output (already in conversation context). Parse `surface=` to determine the OPSX surface level.

**Fallback (if capability line not found):** Read `~/.claude/.skill-registry-cache.json` and extract `openspec_capabilities.surface`.

**Last resort (backwards compatibility):** Run `command -v openspec` to check for CLI availability.

Based on the detected surface:
- `opsx-core` or `opsx-expanded`: Use OPSX commands in later steps.
- `openspec-core`: Use CLI commands directly (no OPSX slash commands available).
- `none`: Use Claude-native fallback templates.

### Step 2: Derive Slugs

**Session state (primary):** Read `~/.claude/.skill-session-token` to get the session token. Then read `~/.claude/.skill-openspec-state-<token>` for pre-populated linkage:
- `changes.<slug>.design_path` — path to the design artifact (e.g., `docs/plans/2026-04-15-feature-design.md`)
- `changes.<slug>.plan_path` — path to the implementation plan (e.g., `docs/plans/2026-04-15-feature-plan.md`); legacy alias: `sp_plan_path`
- `changes.<slug>.spec_path` — path to the acceptance spec (e.g., `docs/plans/2026-04-15-feature-spec.md`); legacy alias: `sp_spec_path`
- `changes.<slug>.capability_slug` — use as capability

If the state file exists and has the relevant change entry, use those values. Skip user prompts for fields that are already populated.

**Fallback (no state file):** Use the existing user-input flow (unchanged from current behavior).

**Change slug (`<feature-name>`):**
- If `plan_path` is provided: strip the leading date prefix from the plan filename stem. E.g., `docs/plans/2026-04-15-openspec-ship-plan.md` → `openspec-ship`.
- If `plan_path` is not provided and no explicit feature name given: ask the user for a kebab-case change name. Do not guess.

**Capability slug (`<capability>`):**
- If the linked SP spec references a specific capability: use that name in kebab-case.
- If not identifiable: ask the user. Do not guess.

### Step 3: Create OR Sync Change Folder

**Pre-flight check:** Does `openspec/changes/<feature-name>/` already exist at the start of this SHIP phase?

- **If YES (spec-driven mode path):** The change folder already exists because it was created upfront during DESIGN phase in a `spec-driven` preset session. Do NOT overwrite `proposal.md` or `design.md` — those are the committed historical decision record. Instead:
  1. Validate the existing change folder structure with `openspec validate <feature-name>` (if CLI available).
  2. Compare the existing `specs/<capability>/spec.md` against as-built code. If implementation diverged from the upfront spec, update `specs/<capability>/spec.md` to reflect what was actually built. Append a brief note at the bottom of `design.md`:
     ```markdown
     ## Implementation Notes (synced at ship time)
     - [describe any deviations from the upfront design]
     ```
  3. Skip to Step 4 (Validate) and continue to Step 5 (Changelog) and Step 6 (Archive).

- **If NO (retrospective mode path):** No upfront change exists. Proceed to create retrospectively — scaffold the change folder and populate it from as-built code and the execution plan.

**Capability taxonomy inference (run BEFORE deciding on `<capability-slug>`):**

Before choosing any capability slug, enumerate existing ones and try to reuse:

```bash
ls openspec/specs/ 2>/dev/null
```

Apply this 3-step heuristic to the enumerated list:

1. **Noun-family match** — if the feature's core domain noun (e.g., "authentication", "billing", "routing") appears verbatim or as a close synonym in an existing capability folder, **extend that capability**. Score: HIGH confidence.
2. **Subsystem overlap** — if the feature touches code paths already covered by an existing capability (check `openspec/specs/<cap>/spec.md` requirements for subsystem references), **extend that capability**. Score: MEDIUM confidence.
3. **Genuinely new surface** — if neither matches and the feature is a distinct subsystem, **create a new capability**. Score: LOW confidence — pause and double-check.

**Decision gate based on confidence:**

- **HIGH or MEDIUM confidence** (match to existing): auto-extend, no prompt. Proceed.
- **LOW confidence** (no clear match): auto-create IS allowed to preserve plug-and-play, but emit the warning below and prefer asking the user first if the session is interactive.
- **AMBIGUOUS** (two existing capabilities look equally applicable): ask the user explicitly — do NOT guess.

**New-capability safeguard:** If creating `openspec/specs/<new-capability>/` for the first time (no existing folder), emit a visible warning in your response:
> ⚠️ NEW CAPABILITY: This change introduces capability `<new-capability>`. Confirm the taxonomy is correct before archive. Prefer extending an existing capability where possible — check `openspec/specs/` for close matches first. Existing capabilities considered and rejected: `<list the enumerated capabilities and the reason each was rejected>`.

The user can then course-correct (rename, merge, or approve) before `openspec-ship` proceeds to archive.

**Bias:** prefer extending an existing capability over creating a new one; err toward fewer, coarser capabilities. Micro-capabilities ("auth-token-rotation", "auth-password-reset", "auth-mfa") fragment review routing and CODEOWNERS enforcement; a single "auth" capability with multiple requirements scales better. Split a capability only when it has clearly separable concerns that belong to different teams.

**Retrospective content (when no upfront change exists):**

**OPSX path (CLI available):**
1. Run `openspec new change <feature-name>` to scaffold the change folder.
2. Populate each artifact with **retrospective** content from the shipped codebase and SP artifacts, not forward-looking proposals. The code is already written — describe what was actually built.

**Important — verb-first CLI commands:** Always use the top-level verb form. The `openspec change ...` subcommands are deprecated. Use:
- `openspec new change <name>` (not `openspec change new`)
- `openspec validate <name>` (not `openspec change validate`)
- `openspec list` (not `openspec change list`)
- `openspec show <name>` (not `openspec change show`)
- `openspec archive <name>` (not `openspec change archive`)

**Fallback path (no CLI):**

Create `openspec/changes/<feature-name>/` with:

**proposal.md** (must match openspec's expected headers exactly):
```
## Why
Why we built this. (Synthesized from SP brainstorming spec if available.)

## What Changes
High-level summary of what was actually built.

## Capabilities

### New Capabilities
- `<capability-name>`: Brief description of what this capability covers

### Modified Capabilities
- `<existing-name>`: What requirement changed

## Impact
Affected code, APIs, dependencies, systems.
```

**design.md:**
```
# Design: <Feature Name>

## Architecture
Data flow, component breakdown, system diagrams reflecting the as-built state.

## Dependencies
New packages, APIs, or database changes introduced.

## Decisions & Trade-offs
Why Path A over Path B. Rejected alternatives and rationale.
(Synthesized from Superpowers brainstorming spec if available.)
```

**specs/<capability>/spec.md** (delta spec, one per capability):

Use RFC 2119 keywords in UPPERCASE: MUST, MUST NOT, SHALL, SHALL NOT, SHOULD, SHOULD NOT, MAY. Never write these as lowercase when they express requirements.

```
## ADDED Requirements

### Requirement: <Name>
<Description using RFC 2119 keywords in UPPERCASE, e.g. "The system MUST ...">

#### Scenario: <Name>
- **WHEN** <condition>
- **THEN** <expected outcome>
```

**tasks.md** (when `plan_path` is provided):
```
# Tasks: <Feature Name>

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

## Completed

- [x] 1.1 <task description> (from SP execution plan) [checkpoint: <sha7>]
- [x] 1.2 <task description>
```

**Checkpoint stamping (issue #129):** while writing the completed-task lines, attribute commits from `git log --oneline --abbrev=7 <merge-base>..HEAD`. Append ` [checkpoint: <sha7>]` ONLY when exactly one in-range commit matches the task by task number or strong keyword — ambiguous or unattributable tasks stay bare (a missing stamp is honest; a guessed one is not). Then run the deterministic integrity floor:

```bash
bash scripts/checkpoint-validate.sh openspec/changes/<feature-name>/tasks.md
```

- Exit 1 (malformed stamp, or SHA outside `merge-base..HEAD`): repair or remove the offending stamps and re-run until clean. Do not proceed to Step 4 with a failing validation.
- Exit 2 (unrunnable): note it in the ship report and continue — never blocking.
- Always copy the `checkpoints: N stamped / M completed tasks` summary line into the ship report (this line is the kill-criterion evidence: two consecutive ships whose checkpoints nobody reads → remove this stamping step).

The validator is scoped to pre-merge feature-branch use only — never run it against archived `tasks.md` files (after squash-merge the branch SHAs are gone from main's history and every stamp would spuriously fail).

**tasks.md** (when `plan_path` is NOT provided):
```
# Tasks: <Feature Name>

## Completed

- [x] 1.1 Retrospective tasks unavailable — no Superpowers execution plan was provided. See git log for implementation history.
```

### Step 4: Validate (CLI only)

If OpenSpec CLI was detected in Step 1:
- Run `openspec validate <feature-name>`.
- On validation failure: STOP. Report the issues for the user to resolve. Do not proceed.
- On validation success: proceed to Step 5.

If CLI is not available: skip this step.

Note: The CLI command is `openspec validate <change>`, not `openspec verify`. The `/opsx:verify` slash command exists as an expanded workflow profile but is not the base CLI command.

### Step 5: Update Changelog

1. Check for `CHANGELOG.md` in the project root.
2. If it exists with a recognizable format, append notes matching that format.
3. If it exists with Keep a Changelog format, append under `## [Unreleased]`.
4. If none exists, create a new `CHANGELOG.md` using Keep a Changelog format:
   ```
   # Changelog

   All notable changes to this project will be documented in this file.

   The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
   and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

   ## [Unreleased]
   ```
5. Categorize entries strictly into `### Added`, `### Changed`, `### Fixed`, or `### Removed`.

### Step 6: Archive & Cleanup

**Archive the change folder:**

**OPSX path (CLI available):**
Run `openspec archive <feature-name>`. This:
1. Checks artifact completion.
2. If delta specs exist, prompts for sync to canonical specs.
3. Moves the change folder to `openspec/changes/archive/YYYY-MM-DD-<feature-name>`.

**Fallback path (no CLI):**
1. Create `openspec/changes/archive/` if it doesn't exist.
2. Move `openspec/changes/<feature-name>/` to `openspec/changes/archive/YYYY-MM-DD-<feature-name>/`.
3. If no canonical spec exists at `openspec/specs/<capability>/spec.md`, create it from the change's delta spec.
4. If a canonical spec already exists, do NOT mutate it. Log: `"Canonical spec exists at openspec/specs/<capability>/spec.md. Skipping canonical update — use OpenSpec CLI for safe merging."`

**Enrich archive with Superpowers artifacts (when plan_path is known):**

1. Parse the `**Spec:**` line from the plan to find the linked SP spec file.
2. Create `openspec/changes/archive/YYYY-MM-DD-<feature-name>/superpowers/`.
3. Move the SP plan file and SP spec file into that `superpowers/` subdirectory.
4. Remove only the specific moved files from `docs/superpowers/`. Do not delete directories or unrelated files.

If `plan_path` is not provided: skip SP artifact archival. Log: `"No Superpowers plan path provided. Skipping SP artifact archival."`

**Write provenance metadata:**

After the archive path exists and SP artifacts (if any) have been moved:
1. Read `~/.claude/.skill-session-token` for the session token.
2. Run the `openspec_write_provenance` helper (source `hooks/lib/openspec-state.sh` from the auto-claude-skills plugin root, then call `openspec_write_provenance "<archive_path>" "<token>" "<change_slug>"`).
3. This creates `<archive_path>/superpowers/source.json` with schema_version, paths, branch, commit, surface, and timestamp.
4. If the write fails, log a warning but do not fail the archive.

### Step 7a-bis: Extract Hypotheses into Session State

If `discovery_path` exists in session state AND the file at that path is readable:

1. Read the `## Hypotheses` section from the discovery artifact
2. Parse each `### H<N>:` entry, extracting:
   - `id` — the hypothesis ID (e.g., "H1")
   - `description` — the prose hypothesis line ("We believe ...")
   - `metric` — from the **Metric:** field
   - `baseline` — from the **Baseline:** field
   - `target` — from the **Target:** field
   - `window` — from the **Window:** field
3. Persist hypotheses and mark the change archived. Source the state helpers from the auto-claude-skills plugin, then call them:

```bash
TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null)"
. "$CLAUDE_PLUGIN_ROOT/hooks/lib/openspec-state.sh"

HYPS='[{"id":"H1","description":"...","metric":"...","baseline":"...","target":"...","window":"..."}]'
openspec_state_set_hypotheses "$TOKEN" "<slug>" "$HYPS"

# Record the ship timestamp so write_learn_baseline captures the real ship time,
# not the stop-hook wall-clock fallback. Call after archival in Step 7b completes,
# or here if archival is already complete.
openspec_state_mark_archived "$TOKEN" "<slug>"
```

If the discovery description contains single-quotes (e.g., "it's faster"), construct the JSON via `jq -n` instead of shell-quoted literals to avoid quoting blow-ups.

If `discovery_path` is absent in session state or the file is unreadable: Skip silently. `hypotheses` stays null in state. This covers sessions that entered at DEBUG or skipped discovery.

### Step 7b: Archive Intent Artifacts

If `discovery_path`, `design_path`, `plan_path`, or `spec_path` exist in session state:

1. Create `docs/plans/archive/` if it doesn't exist
2. Move the discovery, design, plan, and spec files to `docs/plans/archive/`:
   ```bash
   mkdir -p docs/plans/archive
   for f in "$discovery_path" "$design_path" "$plan_path" "$spec_path"; do
     [ -f "$f" ] && mv "$f" docs/plans/archive/
   done
   ```

**Note:** `docs/plans/archive/` is the human-readable intent history. `openspec/changes/archive/` is the OpenSpec change archive. They serve different purposes and coexist.

### Step 7c: Generate Divergences Report

If `design_path` exists in session state and the design file is readable:

1. Read the design artifact's **Acceptance Scenarios** section
2. Read the design artifact's **Capabilities Affected** and **Out-of-Scope** sections
3. Compare against what was actually built (from the OpenSpec change's `proposal.md` and `specs/`)
4. Append a `## Divergences` section to the **archived** design doc:

```markdown
## Divergences (auto-generated at ship time)

**Acceptance Scenarios:**
- [x] GIVEN ... WHEN ... THEN ... — implemented as designed
- [~] GIVEN ... WHEN ... THEN ... — implemented with modification: [describe]
- [ ] GIVEN ... WHEN ... THEN ... — not implemented: [reason]

**Scope changes:**
- Added: [capability not in original out-of-scope or capabilities list]
- Removed: [capability in original list but not implemented]
- Modified: [capability implemented differently than designed]

**Design decision changes:**
- [any trade-offs or approach changes made during implementation]
```

**Important:** Write divergences to the **archived copy** in `docs/plans/archive/`, not the live file. The archive is the historical record; the live file may still be in use if the feature spans multiple sessions.

## Graceful Degradation Summary

| OpenSpec CLI | Behavior |
|-------------|----------|
| Available | `openspec new change` → `openspec validate` → `openspec archive` |
| Not available | Claude-native templates → skip validation → manual archive. Same artifact contract (paths, filenames, section headings). |

## Verification

Before declaring the ship documented, confirm:

- The change folder exists on disk with proposal / design / specs (or the Claude-native fallback produced the same artifact contract) -- verified by listing it, not assumed.
- `openspec validate` ran and passed when the CLI is available; when absent, the skip is stated explicitly.
- The changelog entry was written and the archive step completed (or its absence is reported).
- Hypotheses and the ship timestamp were recorded to session state where applicable.
