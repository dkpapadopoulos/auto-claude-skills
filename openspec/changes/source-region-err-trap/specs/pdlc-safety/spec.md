## ADDED Requirements

### Requirement: A command failing INSIDE a lib sourced by the push gate MUST NOT exit the gate

`hooks/openspec-guard.sh` MUST source every library through a single helper that disarms its fail-open ERR trap for the duration of the load and restores it immediately afterwards. This closes the residual gap recorded by the #137 requirement, which is scoped to the source's own exit status and explicitly does NOT cover a command that fails during the sourced file's execution.

The helper MUST be applied at **every** source site in the hook. Clearing the trap at one site is insufficient: `hooks/lib/phase-attest.sh` re-sources `hooks/lib/session-token.sh`, so a trap restored too early simply fires one lib later.

The helper MUST return the source's own exit status, so that call sites keep the guarded `&&`/`||` form the #137 requirement mandates, and MUST NOT be moved into `hooks/lib/`: sourcing a lib in order to make lib-sourcing safe leaves the load of that helper itself unprotected.

The guarantee is bounded and MUST be stated as such: a lib that FAILS cannot exit the hook. Two things are explicitly outside it. First, a faulty lib is not made to work — sourcing continues past the failing command, so the lib MAY be partially loaded, and callers MUST keep their `command -v <fn>` confirmations and their degradation notes. Second, a lib that calls `exit` still terminates the hook: disarming a trap cannot stop a sourced file exiting the shell it is sourced into, and measured, `exit` in any of the ten libs sourced above the deny sites produces empty stdout. Closing that would require a subshell pre-probe per lib on the hot path and is NOT done here; the limit is recorded rather than implied, because a guarantee stated more broadly than it holds is the failure this capability exists to prevent.

#### Scenario: A sourced lib runs a failing command before defining anything

- **WHEN** a lib the guard sources runs `false`, hits a command-not-found, or performs a failing `X="$(cd … && pwd)"` assignment before its definitions, and a `git push` command is submitted
- **THEN** sourcing continues, the lib's functions are defined, and the guard emits the same decision it emits when the lib is healthy — rather than exiting 0 with empty stdout, which the harness cannot distinguish from an allow

#### Scenario: A sourced lib fails after its definitions

- **WHEN** the failing command is also the source's last command, so the source's exit status is non-zero although every function is defined
- **THEN** the guard degrades exactly as it does for an ABSENT lib — it emits the degradation advisory naming that lib — and MUST NOT emit empty stdout

#### Scenario: The guard is never silent about a lib fault

- **WHEN** any lib the guard sources fails in any of these ways
- **THEN** the guard's stdout is non-empty: either a `permissionDecision` or an announced degradation, because empty stdout is indistinguishable from a deliberate allow

#### Scenario: A healthy install is unaffected

- **WHEN** every lib loads cleanly
- **THEN** the guard's output is byte-identical to the pinned healthy-control baseline — this change adds output on fault paths only

### Requirement: The runtime bypass MUST be pinned by executing the real guard, not by linting it

A test SHALL drive `hooks/openspec-guard.sh` itself, over a matrix of every gate-enforcement lib the guard sources plus `hooks/lib/phase-attest.sh` (which re-sources another lib and so re-arms the trap), each fault shape in the table above, and both injection points — before and after the lib's definitions. Fault shapes SHALL be committed fixture files, one shape per file. The matrix population is deliberately narrower than the set of libs the guard sources: the remaining ones are diagnostic or advisory and carry no decision.

Expected outcomes MUST be derived from the real guard within the same run — the healthy control and the absent-lib baseline — and MUST NOT be hand-written, since a hand-written expectation proves only that the test agrees with itself. Each cell MUST assert that the injected fault actually changed the lib file, so a fixture that silently failed to apply cannot turn the matrix into a set of healthy runs.

The static, status-only lint MUST NOT be widened to claim this coverage. It inspects call sites, it stayed green through every silent allow this requirement closes, and relabelling it would recreate the false confidence its own scope note exists to prevent.

#### Scenario: The fix is reverted

- **WHEN** `hooks/openspec-guard.sh` is restored to its pre-fix state and the matrix is run
- **THEN** the fault cells fail, because they observe empty stdout where a decision is required

#### Scenario: A protection is present but inert in the shipped configuration

- **WHEN** the helper carries two independent protections and only one of them is exercised by the hook's current settings — here the explicit `trap - ERR`, inert because the hook sets no `set -E`
- **THEN** a test SHALL pin the inert one under the configuration where it IS load-bearing, driving the helper text EXTRACTED from the hook rather than a restatement of it, with a red control that removes only that protection — otherwise deleting it leaves the whole matrix green and the documented rationale describes something no test defends

#### Scenario: A skip does not skip

- **WHEN** the test cannot run for lack of a dependency and prints a SKIP
- **THEN** it exits, rather than printing a summary helper that merely returns and letting the body run anyway

#### Scenario: A passing cell allowed the push

- **WHEN** a cell's accepted baseline is an announced degradation, which for some libs is an ALLOW where the healthy outcome is a DENY
- **THEN** the assertion label names which outcome occurred, so a fully green run cannot be read as "the gate held in every cell"

#### Scenario: The harness stops injecting

- **WHEN** an injection silently becomes a no-op, so every cell runs against a pristine lib
- **THEN** the test fails — both on the per-cell change assertion and on the red control, which requires an aborted source to remain distinguishable from a healthy run

### Requirement: A helper that wraps a source MUST be treated as a source by the status-only lint

Where a hook routes its sources through a helper, the #137 lint's matcher SHALL treat calls to that helper as source lines. Renaming the call form otherwise removes those sites from the lint's own population while every assertion it makes about them continues to pass, vacuously — measured here as a drop from 13 matched lines to 1 in `hooks/openspec-guard.sh`, including the site the lint pins as never-allowlistable.

The call shape remains decisive and MUST keep the #137 form. A helper that returns the source's exit status makes a bare call a failing simple command at top level, which trips the ERR trap and produces the same silent allow the helper exists to prevent.

#### Scenario: A source-wrapping helper is called without a guard

- **WHEN** a hook carrying an ERR trap calls the helper as a bare statement, outside any `&&`/`||` list
- **THEN** the lint fails and names the file and the offending line, exactly as it would for a bare `. lib`

#### Scenario: Sources are routed through a new helper

- **WHEN** a future change introduces another wrapper around `.`/`source`
- **THEN** that wrapper is added to the lint's matcher in the same change, so the sites it now owns stay inside the lint's population

#### Scenario: A wrapper is renamed without updating the matcher

- **WHEN** the helper is renamed and the lint's matcher is not updated, so its matched-line population for `hooks/openspec-guard.sh` collapses
- **THEN** the lint fails on a population floor over matched source LINES — a file-count check does not cover this, which is why the original 13-to-1 collapse passed every assertion, and prose in this spec is not a gate

### Requirement: A source-wrapping helper MUST be re-entrant

The helper MUST restore the ERR trap only when the outermost load completes. An unconditional re-arm restores the trap while an outer source is still executing, so a lib that itself calls the helper re-exposes the very failure the helper prevents — the "one site is not enough" problem, recursed. This is required even while no lib calls the helper, because the stated justification for keeping the explicit trap disarm is that it continues to hold if the hook ever adds `set -E`, and that is exactly the configuration in which a non-re-entrant re-arm fails.

#### Scenario: A sourced lib calls the helper

- **WHEN** the hook runs under `set -E` and a lib loaded through the helper itself loads another lib through it, then fails after the inner load returns
- **THEN** the hook survives to its decision, because the trap is restored only at depth zero

### Requirement: Hooks still exposed to this class MUST be named, not implied

The scope note of the static lint SHALL name every remaining ERR-trap hook that sources libs directly, and state why each is out of scope. A residual gap recorded as "some other hooks" is indistinguishable from one nobody looked for.

#### Scenario: A reader asks what is still exposed

- **WHEN** the lint's scope note is read
- **THEN** it names `compact-recovery-hook.sh`, `compact-recovery-prompt-hook.sh`, `consolidation-stop.sh`, `skill-completion-hook.sh` and `skill-gate.sh` as still exposed, records that none gates an outbound action, and records that `publish-guard.sh` — the other outbound deny — sources nothing at all
