## Why

Inside a composition chain the activation hook re-emits the chain's current step as `MUST INVOKE` on every later prompt of six words or fewer that selects no process skill of its own. "go", "yes" and "thanks" each receive a 2.6–6 KB block for a step the session has already been shown. Over five and a half weeks of the owner's sessions, 92 of 451 mandated blocks on typed prompts were of that kind; four of the 92 were followed by the mandated skill being invoked in the same turn.

The measurement behind issue #333 (83 wrong mandates against 11 right) replayed each prompt in a fresh session, so it contained none of these. They are a separate slice of the routing-precision problem.

Whether hiding them helps is not known. A repeated reminder may be what keeps an unfinished review in view. So this change adds the rule and the means to find out, and turns nothing on.

## What Changes

- **A display rule, shipped in shadow.** When the block's process mandate was injected by sticky composition, the block carries no other skill, and the session has already been shown that step on the same chain (since the user last asked for a process step in their own words, and since the last compaction), the rule would hide the block. By default it hides nothing: the hook displays exactly as before and writes one small record per mandated block under `~/.claude/.sticky-repeat-shadow.d/` (no prompt text).
- **`ACS_STICKY_REPEAT`** selects `shadow` (default), `trial` (hide in half the sessions, fixed per session by its token), `suppress`, or `off`. An unrecognised value is `shadow`.
- **Display-only.** Scoring, the chain walk and every pre-existing state write are unchanged in every mode. The rule's own two files are written after all of them and are read by no gate.
- **A per-session marker** of which steps were shown, scoped to the chain, removed at compaction and by the session-start cleanup. It is believed only as a plain file written for the current chain.
- **Nothing of the rule's is modified in place.** The marker is replaced by an exclusive create and a rename; each record is its own exclusively created file. A name that has been linked onto a routing-state file cannot be used to write into it.
- **The instruments** (`tests/probes/routing-precision/`): row extraction that keeps labellers blind to the rule, the labelling rubric, the stage A scorer and the stage B trial reader.
- **The pre-registration** (`docs/plans/2026-10-05-routing-precision-prereg.md`): two stages. Labels decide whether a randomized trial is worth running; only the trial may license making suppression the default.

## Capabilities

### Modified Capabilities

- `skill-routing`: a sticky-repeat display rule exists in shadow mode; its switch, its record and its display-only guarantee.

## Impact

- `hooks/skill-activation-hook.sh` — the rule, its switch, the marker and the record.
- `hooks/pre-compact-hook.sh`, `hooks/compact-recovery-hook.sh` — remove the marker at compaction (the first fires for automatic compaction too).
- `hooks/session-start-hook.sh` — the marker joins the stale-state cleanup.
- `tests/test-activation-sticky-repeat.sh`, `tests/test-routing-precision-probe.sh` (new); `tests/test-push-gate-display-suppression.sh` (new cells for the gate's decision).
- `tests/probes/routing-precision/` (new), `README.md`, `CHANGELOG.md`.

**What a user sees after installing this: nothing different.** One small local record file is written per mandated prompt (under 500 bytes; nothing prunes them, so `ACS_STICKY_REPEAT=off` is the way to stop it).
