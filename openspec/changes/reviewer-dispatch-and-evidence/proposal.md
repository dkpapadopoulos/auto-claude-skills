# Proposal: authorize reviewer dispatch, name a reviewer that exists, and observe that one ran

## Why

A live session stalled at the REVIEW phase. The model would not dispatch a code
reviewer and asked the user to approve the dispatch instead. The user's ruling:

> The user should not be expected to approve the dispatch of a reviewer agent
> directly. If a review is needed, auto-claude-skills should dispatch the
> reviewer as needed. This needs fixing at the skill / plugin level.

Investigation found **three independent defects** behind that one symptom. Each
is sufficient on its own to prevent a review from happening.

### 1. No standing authorization exists, so the harness default wins

The harness system prompt carries `Do not call the AgentTool unless the user
requested it`. Precedence in this stack is **user instruction > skill > default
behavior** (`superpowers:using-superpowers`, "User Instructions"). So that line
outranks `skills/agent-team-review/SKILL.md`'s unconditional "### 2. Spawn
Reviewers" step. The skill was the only thing asking for dispatch, and a skill
cannot outrank a user-level instruction.

The string appears nowhere in this repo, nowhere in `~/.claude/settings.json`,
and nowhere in the user's `CLAUDE.md` — it is harness-level and not editable
from the plugin. The plugin therefore cannot *remove* the constraint. It can
only **satisfy** it, by making the user's authorization explicit, durable, and
present at the moment REVIEW routes.

### 2. The plugin instructs dispatching an agent that does not exist

Five call sites tell the model to dispatch `superpowers:code-reviewer`:

- `hooks/skill-activation-hook.sh:1478` (REVIEW red flag)
- `config/default-triggers.json:141`, `:1480`
- `config/fallback-registry.json:154`, `:1350`

The `superpowers` plugin ships **no `agents/` directory at all** — that agent
type is not registered. Superpowers' own `skills/requesting-code-review/SKILL.md:34`
says to dispatch a **`general-purpose`** subagent filled from its
`code-reviewer.md` template. The installed reviewer agents are
`pr-review-toolkit:code-reviewer` and `feature-dev:code-reviewer`.

So even with authorization granted, the literal instruction is unfollowable. A
model that obeys it exactly gets an invalid `subagent_type`; a model that
improvises is guessing.

### 3. The REVIEW milestone is credited for invoking a skill, not for reviewing

`hooks/skill-completion-hook.sh:107-114` records the `requesting-code-review`
gating milestone from `PostToolUse` on `^Skill$` — i.e. the instant `Skill()`
**returns its instructions**. No reviewer has run at that point and none is
required to. The push gate's REVIEW leg (`hooks/openspec-guard.sh:538-544`,
`:800-812`) then reads that milestone and goes green.

Net effect: the gate certifies "REVIEW completed" for a branch on which no
reviewer was ever dispatched. Recorded independently in the user's memory as
`review-gate-credits-invocation-not-work.md`.

**Compounding fact:** `hooks/hooks.json` registers `PostToolUse` on `^Task$`,
but this harness names the subagent tool **`Agent`** — verified across 12
local transcripts (`tool_use` name `Agent`; input keys `description`, `model`,
`name`, `prompt`, `run_in_background`, `subagent_type`). Any hook keyed only to
`^Task$` is dead on current Claude Code.

## What Changes

1. **`phase_enforcement.review_dispatch` config key** (`~/.claude/skill-config.json`),
   default `auto`, opt-out `ask`. Rendered by `hooks/skill-activation-hook.sh`
   into REVIEW-phase context as a standing authorization to dispatch reviewer
   subagents without a per-dispatch approval. Joins the existing
   `phase_enforcement.*` namespace already read by `openspec-guard.sh:862` and
   `skill-gate.sh:86`.

   **Scope is deliberately narrow: read-only reviewer agents only.** Agents that
   can `Edit`/`Write`/push/call outbound APIs are excluded and keep asking.

2. **Correct the reviewer agent name** in all five call sites: dispatch
   `general-purpose` with the superpowers `code-reviewer.md` template, or an
   installed reviewer agent when one is present.

3. **Reviewer-ran evidence** — a new `PostToolUse` hook matching `^(Task|Agent)$`
   records a distinct `reviewer-ran` key into the existing per-(repo+branch)
   branch ledger (`hooks/lib/branch-ledger.sh`) when a reviewer agent returns
   successfully. The push gate gains a REVIEW-evidence leg that reads it.

   The leg is a **single shared predicate called from both sites that gate
   `requesting-code-review`** — the chain-scoped check (`openspec-guard.sh:534-548`)
   and the repo-wide global fail-closed gate (`:797-829`). Teaching only the
   first would leave the second passing on the old milestone alone, and this
   repo's own pushes traverse the second.

   **Ships warn-first** — appends to `_STALE_MSG`, sets no `permissionDecision`.
   The deny-flip is pre-registered (see `design.md`) with **both** a sample-size
   floor (n=29) and a calendar deadline (2026-11-30).

4. **`^Task$` → `^(Task|Agent)$`** on the existing `PostToolUse` matcher in
   `hooks/hooks.json`, so subagent-keyed hooks fire on current Claude Code.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: adds a standing reviewer-dispatch authorization rendered at
  REVIEW, and a warn-first reviewer-ran evidence leg on the outbound push/merge
  gate distinguishing "the review skill was invoked" from "a reviewer ran".

## Impact

- `hooks/skill-activation-hook.sh` — REVIEW-phase authorization render; agent-name fix.
- `hooks/reviewer-evidence-hook.sh` — **new**, `PostToolUse ^(Task|Agent)$`.
- `hooks/hooks.json` — register the new hook; widen the existing `^Task$` matcher.
- `hooks/openspec-guard.sh` — warn-first reviewer-evidence leg on the REVIEW path.
- `config/default-triggers.json`, `config/fallback-registry.json` — agent-name fix.
- `skills/agent-team-review/SKILL.md` — dispatch step states the authorization.
- `docs/` — config key documented.

## Why not deny immediately

The user's first instinct — and this author's first recommendation — was to make
the reviewer-ran evidence a hard requirement. Two findings overturned it:

- **This repo has already paid for that exact mistake.** `openspec/changes/implement-evidence-gate/proposal.md:7`:
  *"shipped **warn-first and proven before deny**, per this repo's backtest
  discipline (deny variants that shipped without a backtest ran **56–94%
  false-block** and were disabled)."*
- **It would block in-flight work on day one.** 8 live branch ledgers under
  `~/.claude/.skill-branch-ledger-*` currently carry `requesting-code-review`;
  none can carry `reviewer-ran`. Every one of those branches, including the one
  this change is developed on, would be denied at first push.

Defects 1 and 2 mean reviewers now actually run, so the green-without-review
hole closes **behaviorally** in this same change. The evidence leg exists to
measure the residual — and denying on an unmeasured predicate is the documented
56–94% failure mode.
