# Design: PATH-independent Serena MCP registration + self-heal

## Architecture

All new logic lives in `hooks/lib/serena-autoregister.sh` (a sourceable,
Bash-3.2-compatible lib already sourced by `hooks/session-start-hook.sh:1062`).
Three units:

### 1. `serena_resolve_bin` — absolute-path resolver

Echoes an absolute, executable serena path to stdout; returns non-zero and
echoes nothing when none is found.

Resolution order:
1. `command -v serena` (already an absolute path when serena is on PATH).
2. Probe, first executable wins:
   - `$HOME/.local/bin/serena` (uv tool default)
   - `$HOME/.local/share/uv/tools/serena-agent/bin/serena` (uv tool target)
   - `$HOME/.cargo/bin/serena`

The probe is the load-bearing part of self-heal: in the exact failure case the
session-start hook's own PATH also lacks `~/.local/bin`, so `command -v serena`
fails there too — only the probe can recover the path.

### 2. Auto-register fix (`serena_maybe_autoregister`)

Unchanged eligibility gate (still fires only when serena is genuinely reachable).
The single change: capture `SERENA_BIN="$(serena_resolve_bin)"` and register
`-- "$SERENA_BIN" start-mcp-server …` instead of bare `serena`. When
`command -v serena` succeeds (the gate), the resolver returns that same absolute
path, so behavior is identical except the stored command is now absolute.

### 3. Self-heal (`serena_maybe_migrate_bare_registration`)

Called from session-start immediately after `serena_maybe_autoregister`, guarded
by the same `. lib && fn || true` form (never the bare-source bypass shape).

- **Marker:** `~/.claude/.auto-claude-skills-serena-abspath-migrated`. Present →
  cheap `[ -e ]` no-op. Runs at most once per machine.
- **Fires only when ALL hold:** `claude` CLI present; a `serena` registration
  exists; its command is bare `serena` (no `/`); `serena_resolve_bin` yields an
  absolute path; the existing scope + args are readable.
- **Rewrite mechanism:** the `claude mcp` CLI (`remove` then `add`), NOT a raw
  `~/.claude.json` edit — Claude Code owns that file, so the CLI performs the
  write with its own locking. The absolute path is resolved *before* `remove`, so
  a resolver failure never leaves the reg deleted. Scope and args are read
  (read-only) from the existing entry and reproduced on `add`.
- **Fail-open:** any missing precondition or error → skip; the marker is still
  written to prevent per-session retries, and a breadcrumb
  (`~/.claude/.auto-claude-skills-serena-abspath-migrate-error`) records a failed
  rewrite for `/setup` to surface. The function never returns non-zero.

## Trade-offs

- **CLI rewrite vs. in-place jq edit of `~/.claude.json`.** Chosen: CLI. Faithful
  scope/arg preservation is trickier via CLI, but it avoids racing Claude Code's
  own writes to `~/.claude.json`. A one-time in-place jq edit was the alternative;
  rejected because an every-session-start hook mutating the app's live state file
  is a worse failure mode than a missed exotic-path self-heal.
- **Fixed probe list.** Three known dirs cover uv-tool and cargo installs. A
  custom `PATH`-only install location won't self-heal automatically but still
  works via a `/setup` re-run. Accepted — matches the fitted-list-not-search
  posture used elsewhere.
- **Marker = once.** A user who later adds a *second* broken registration won't
  be re-healed; the new-registration fix covers all future adds with an absolute
  path, so this is a bounded, shrinking population.

## Dissenting views

- "Just make session-start prepend `~/.local/bin` to PATH." Rejected: it fixes
  the hook's PATH but not the MCP client's spawn environment, which is the actual
  failure surface; and it silently changes PATH semantics for everything
  downstream in the hook.
- "Advisory-only, no automatic rewrite." Rejected by the approved scope — the
  user explicitly wants existing broken registrations self-healed, not just
  flagged. The breadcrumb + `/setup` path remain as the fallback when automatic
  rewrite can't run.

## Decisions

- Absolute path is stored verbatim from the resolver (symlink path such as
  `~/.local/bin/serena` is preferred over its realpath — it survives
  `uv tool upgrade`, whose target dir is stable but whose venv contents change).
- Verification is deterministic: standard TDD, no eval set. Trifecta < 2
  (local-only outbound), so no agent-safety-review gate.

## Out-of-scope

- Forgetful MCP registration, LSP plugins, changing the Serena install method,
  and any general MCP-registration refactor.
