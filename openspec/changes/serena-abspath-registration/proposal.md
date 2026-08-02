# Proposal: PATH-independent Serena MCP registration + self-heal

## Why

The plugin registers the Serena MCP server with a **bare `serena` command**
(`hooks/lib/serena-autoregister.sh` and `commands/setup.md`). When Claude Code
is launched from a GUI (Dock/Spotlight) or any environment that does not source
the user's shell rc, the process PATH does **not** include `~/.local/bin` — the
directory `uv tool install` puts the `serena` symlink in. The MCP client then
cannot spawn the bare `serena` command and reports `✘ Failed to connect`
(`serena_connected=false` at session start).

This was hit live on 2026-08-02: a registration that worked from a terminal
launch silently failed under GUI launch. Editing `~/.zshrc` does not fix it,
because the app's spawn environment never sources `.zshrc`.

## What Changes

1. **New shared helper `serena_resolve_bin`** — resolves an absolute serena path
   via `command -v serena`, falling back to probing known install dirs
   (`~/.local/bin`, `~/.local/share/uv/tools/serena-agent/bin`, `~/.cargo/bin`).
2. **Auto-register uses the absolute path** — `serena_maybe_autoregister`
   registers `"$SERENA_BIN" start-mcp-server …` instead of bare `serena`.
3. **`/setup` docs use the absolute path** — the three `claude mcp add` snippets
   in `commands/setup.md` register `"$(command -v serena)"` with a one-line note
   on why bare `serena` is fragile.
4. **Self-heal existing registrations** — a new `serena_maybe_migrate_bare_registration`,
   called once from session-start (marker-guarded, fail-open), detects a bare
   `serena` registration and rewrites it to the resolved absolute path via the
   `claude mcp` CLI, preserving scope and args.

## Capabilities

### Modified
- **serena-mcp-registration** — how the plugin registers and repairs the Serena
  MCP server so the registration is robust across launch environments.

## Impact

- Affected code: `hooks/lib/serena-autoregister.sh` (helper + fix + self-heal),
  `hooks/session-start-hook.sh` (call self-heal), `commands/setup.md` (docs).
- Affected tests: `tests/test-serena-autoregister.sh` (extended).
- No change to how Serena is installed, to Forgetful MCP, or to LSP plugins.
- Touches `hooks/` — routing-governance push gate requires a clean
  `project-verification` verdict before push (dogfooding).
