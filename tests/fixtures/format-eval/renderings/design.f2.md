---
type: design
status: approved
date: 2026-05-23
change_slug: serena-auto-register
capabilities: [skill-routing, setup]
---

# Serena Auto-Register on First Session — Design

**Date:** 2026-05-23
**Status:** Approved (DESIGN → PLAN)
**Slug:** serena-auto-register

## Problem

Users with `serena` installed on PATH still see `serena_connected=false` (and often `serena=false` too) unless they explicitly run `/setup` to register Serena as an MCP server. The friction case is real: today's own session shows `serena=true, serena_connected=false`, and most users will not realize that running `/setup` is the prerequisite for the plugin's Serena-aware skill routing to take effect.

The desired outcome: any user who installs the `auto-claude-skills` plugin and has Serena on PATH gets Serena auto-registered as an MCP server without intervention. `/setup` remains the explicit entry point for richer onboarding (project-yml init, language detection, hooks, upgrades) — but the bare-minimum MCP wiring should be zero-touch.

## Capabilities Affected

- **`skill-routing`** — `hooks/session-start-hook.sh` gains a new step that runs before the existing `context_capabilities` detection. The new step auto-registers Serena if eligible, so the existing `.serena = true` augmentation (which reads `~/.claude.json`) sees the registration on the same session.
- **`setup`** — `commands/setup.md` gains a "re-trigger auto-registration" entry point: deleting the marker file is the documented recovery path when a user wants the plugin to re-attempt auto-registration (e.g., after manually removing Serena to fix a broken venv and reinstalling).

## Out of Scope

- **`.serena/project.yml` initialization and language detection.** These remain `/setup`-only. They require user prompts and project-specific judgment; not safe to run silently on every fresh project.
- **Upgrading old `uvx --from git+` Serena installs.** Disruptive (removes existing registration, reinstalls binary). Stays manual via `/setup`.
- **serena-hooks installation (`auto-approve`, `remind`, `cleanup`).** These mutate the user's `~/.claude/settings.json` hooks block and are a separate consent decision. Stay `/setup`-gated.
- **Auto-registration of other MCPs (Forgetful, Context7, PostHog).** Out of scope for this change. Same pattern could be applied later if validated here, but each MCP has different consent/install considerations and should be evaluated independently.
- **`SERENA_CONNECTION_CHECK=1` default flip.** Independent decision; this design only addresses *registration*. The connection-check env var controls whether the session-start hook also probes `claude mcp list` for the `✓ Connected` marker after the fact — orthogonal to whether registration happened at all.
- **Project-scope or local-scope registration.** This change registers Serena once with `--scope user`. Per-project registration is explicitly rejected (see Approach).

## Approach

**Trigger:** On session start, inside `hooks/session-start-hook.sh`, run a new helper `_maybe_auto_register_serena` *before* the existing `context_capabilities` augmentation block (the `($all_mcp | has("serena"))` check at line ~797).

**Eligibility (all must be true):**
1. `command -v serena` succeeds (binary is on PATH).
2. `command -v claude` succeeds (we need the CLI to register).
3. Marker file `~/.claude/.auto-claude-skills-serena-registered` does NOT exist.
4. `claude mcp list` does NOT already contain a `serena` entry (matched by `^serena: ` line prefix, same pattern as the existing `SERENA_CONNECTION_CHECK` block at line ~812).

**Action when eligible:**
```bash
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd
```
This is the exact canonical command already documented in `commands/setup.md` (line 264).

**Post-action:**
- On success (exit 0): write marker file `~/.claude/.auto-claude-skills-serena-registered` with a one-line timestamp.
- On failure (non-zero): write the marker anyway, plus an error breadcrumb. Rationale: a failing `claude mcp add` will fail every session — don't spam retries. Write a separate breadcrumb file `~/.claude/.auto-claude-skills-serena-register-error` that surfaces the error on next `/setup` invocation.
- In both cases: emit a `[serena-autoregister]` line to stderr only when `SKILL_EXPLAIN=1` (consistent with the existing `[design-guard]` and other debug breadcrumbs).

**Fail-open invariants (mandatory, match existing hook patterns):**
- All checks gated on `command -v` of the tool used.
- All `claude mcp ...` calls have `2>/dev/null || true` semantics; never propagate non-zero exit.
- jq is *not* required for this path (no JSON parsing — only `grep -F`).
- Latency budget: the eligibility checks (3× `command -v` + 1× `claude mcp list | grep`) must add <100ms when the marker exists and Serena is already registered (the steady-state path). When auto-registration actually fires (once per user, ever), latency is dominated by `claude mcp add` which takes ~200-500ms.

**`/setup` integration:**
- Add a new step early in `commands/setup.md` Serena section: "If `~/.claude/.auto-claude-skills-serena-registered` exists and you want the plugin to re-attempt auto-registration, delete it first." This is a documentation-only change; `/setup` itself continues to use its own (richer) registration flow.
- Surface the error breadcrumb if `~/.claude/.auto-claude-skills-serena-register-error` exists.

**Why first-time-only + user-scope was chosen** (selected via brainstorming):
- **Zero-touch first session** — matches the user's stated goal.
- **Respects user state** — if the user later removes Serena's MCP registration manually (broken venv, switching projects, debugging), the plugin doesn't fight them by re-adding it.
- **Cheap steady state** — after the marker exists, only a stat call adds latency (~1ms).
- **User scope** — one registration covers every project; matches the trigger (binary on PATH = global resource). Project scope would require per-project markers and per-project auto-registration, which compounds the side-effect surface across every new repo the user opens.
- **`/setup` remains the recovery handle** — explicit, documented, deterministic.

## Acceptance Scenarios

**Scenario 1: Fresh user with Serena installed, no MCP registration**
```
GIVEN  `command -v serena` returns /usr/local/bin/serena
  AND  `claude mcp list` contains no `serena` entry
  AND  `~/.claude/.auto-claude-skills-serena-registered` does not exist
WHEN   the user starts a Claude Code session in any project
THEN   the plugin runs `claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd`
  AND  writes `~/.claude/.auto-claude-skills-serena-registered` (timestamp inside)
  AND  the same session's context_capabilities augmentation reports `serena=true`
  AND  with SERENA_CONNECTION_CHECK=1, reports `serena_connected=true`
```

**Scenario 2: User has existing Serena registration (any vintage)**
```
GIVEN  `claude mcp list` already contains `serena: <command>`
  AND  the marker file does not exist
WHEN   session starts
THEN   the plugin skips `claude mcp add` (idempotent — registration already present)
  AND  writes the marker file (records that auto-registration was considered and resolved)
  AND  subsequent sessions are no-op (cheap marker check)
```

**Scenario 3: User intentionally removed Serena after auto-registration**
```
GIVEN  the marker file exists (`~/.claude/.auto-claude-skills-serena-registered`)
  AND  the user has run `claude mcp remove serena` manually
WHEN   they start a new session
THEN   the plugin does NOT re-add Serena (marker prevents it)
  AND  routing falls back to non-Serena behavior (matches user intent)
  AND  the user can run `/setup` (or delete the marker) to opt back in
```

**Scenario 4: Serena binary not installed**
```
GIVEN  `command -v serena` returns nothing
WHEN   session starts
THEN   no MCP registration attempt is made
  AND  marker file is not written
  AND  behavior is identical to today (zero side effects)
```

## Decision

**Approved approach:** First-time-only auto-registration with user-scope, gated on `command -v serena`, protected by a marker file at `~/.claude/.auto-claude-skills-serena-registered`. `/setup` remains the explicit, richer entry point and the documented recovery path.

**Next:** Transition to PLAN phase (writing-plans skill) to break this into discrete tasks (helper function, marker file format, session-start integration, `/setup` doc update, tests, changelog).
