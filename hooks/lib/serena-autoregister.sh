#!/usr/bin/env bash
# serena-autoregister.sh — First-time auto-registration of Serena MCP server.
#
# Sourceable lib. Exposes one function: serena_maybe_autoregister.
#
# Behavior (all checks fail-open; function NEVER propagates non-zero):
#   1. Skip if marker file exists at ~/.claude/.auto-claude-skills-serena-registered
#   2. Skip if `serena` is not on PATH
#   3. Skip if `claude` CLI is not on PATH
#   4. If `claude mcp list` already contains a `serena:` entry → skip add, write marker
#   5. Otherwise: run `claude mcp add --scope user serena -- serena start-mcp-server
#      --context claude-code --project-from-cwd --open-web-dashboard false`.
#      The `--open-web-dashboard false` flag suppresses the browser tab Serena
#      would otherwise open on every Claude Code session start (the dashboard
#      itself remains accessible at http://localhost:24282/dashboard/ for users
#      who want it). Write marker on either outcome (success or failure). On
#      failure also write an error breadcrumb that /setup can surface.
#
# Bash 3.2 compatible. jq NOT required on this path.
# Design: docs/plans/2026-05-23-serena-auto-register-design.md

# serena_resolve_bin — echo an absolute, executable serena path (rc 0), or
# echo nothing and return 1. Tries PATH first, then a fixed probe list so the
# path resolves even when the caller's PATH lacks the uv-tool bin dir (the
# exact GUI-launch failure this lib repairs). Bash 3.2; no external deps.
serena_resolve_bin() {
    local p
    p="$(command -v serena 2>/dev/null)"
    if [ -n "${p}" ] && [ -x "${p}" ]; then
        printf '%s\n' "${p}"
        return 0
    fi
    local cand
    for cand in \
        "${HOME}/.local/bin/serena" \
        "${HOME}/.local/share/uv/tools/serena-agent/bin/serena" \
        "${HOME}/.cargo/bin/serena"; do
        if [ -x "${cand}" ]; then
            printf '%s\n' "${cand}"
            return 0
        fi
    done
    return 1
}

serena_maybe_autoregister() {
    local marker="${HOME}/.claude/.auto-claude-skills-serena-registered"
    local err_breadcrumb="${HOME}/.claude/.auto-claude-skills-serena-register-error"

    # 1. Idempotency: marker exists → fully no-op
    [ -e "${marker}" ] && return 0

    # 2. Eligibility: serena binary on PATH
    command -v serena >/dev/null 2>&1 || return 0

    # 3. Eligibility: claude CLI on PATH
    command -v claude >/dev/null 2>&1 || return 0

    # 4. Already-registered short-circuit. Match the line-prefix pattern used
    #    by hooks/session-start-hook.sh for SERENA_CONNECTION_CHECK so the
    #    detection contract stays consistent.
    if claude mcp list 2>/dev/null | grep -q '^serena: '; then
        printf '%s\t%s\talready-registered\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] already-registered, marker written" >&2
        return 0
    fi

    # 5. Auto-register. --project-from-cwd lets Serena pick the active project
    #    per-session without binding the user-scoped registration to one path.
    #    --open-web-dashboard false suppresses the per-session browser tab that
    #    Serena opens by default; the dashboard remains reachable at
    #    http://localhost:24282/dashboard/ for users who want it.
    local serena_bin
    serena_bin="$(serena_resolve_bin)" || serena_bin="serena"
    local add_output add_rc
    add_output="$(claude mcp add --scope user serena -- "${serena_bin}" start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false 2>&1)"
    add_rc=$?

    if [ "${add_rc}" -eq 0 ]; then
        printf '%s\t%s\tregistered\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] registered successfully, marker written" >&2
    else
        # Failure path: write marker so we don't spam retries every session.
        # Also write an error breadcrumb /setup can surface.
        printf '%s\t%s\tregister-failed\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$$" >"${marker}" 2>/dev/null || true
        printf '%s\trc=%s\noutput:\n%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "${add_rc}" "${add_output}" >"${err_breadcrumb}" 2>/dev/null || true
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] claude mcp add failed (rc=${add_rc}); marker + error breadcrumb written" >&2
    fi

    return 0
}

# serena_maybe_migrate_bare_registration — one-time self-heal of an existing
# Serena registration whose command is a bare `serena` (fails under a launch
# whose PATH lacks the uv-tool bin dir). Detects via a read-only jq read of
# ~/.claude.json (current-project/local scope takes precedence over user scope),
# rewrites to the absolute path via the claude CLI preserving scope + args.
# Marker-guarded; fail-open in all branches; NEVER returns non-zero.
serena_maybe_migrate_bare_registration() {
    local marker="${HOME}/.claude/.auto-claude-skills-serena-abspath-migrated"
    local err="${HOME}/.claude/.auto-claude-skills-serena-abspath-migrate-error"
    local cfg="${HOME}/.claude.json"

    [ -e "${marker}" ] && return 0
    command -v claude >/dev/null 2>&1 || return 0   # no CLI → retry a later session
    command -v jq >/dev/null 2>&1 || return 0       # no jq → cannot detect; retry later
    [ -f "${cfg}" ] || return 0

    # Locate the effective serena entry: local (current project) wins over user.
    local scope cmd
    cmd="$(jq -r --arg p "${PWD}" '.projects[$p].mcpServers.serena.command // empty' "${cfg}" 2>/dev/null)"
    if [ -n "${cmd}" ]; then
        scope="local"
    else
        cmd="$(jq -r '.mcpServers.serena.command // empty' "${cfg}" 2>/dev/null)"
        [ -n "${cmd}" ] && scope="user"
    fi
    [ -n "${cmd:-}" ] || return 0                   # no serena reg anywhere → nothing to heal

    # Already absolute → healthy; stop re-checking.
    case "${cmd}" in
        */*) : >"${marker}" 2>/dev/null || true; return 0 ;;
    esac

    # Bare command → attempt rewrite. From here on, an attempt was made: write
    # the marker on every exit so we don't retry every session.
    local serena_bin
    if ! serena_bin="$(serena_resolve_bin)"; then
        printf '%s\tserena unresolvable; left bare reg intact\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" >"${err}" 2>/dev/null || true
        : >"${marker}" 2>/dev/null || true
        return 0
    fi

    # Read args (may contain spaces in a --project path) into an array.
    local args=()
    local a
    if [ "${scope}" = "local" ]; then
        while IFS= read -r a; do args+=("${a}"); done \
            < <(jq -r --arg p "${PWD}" '.projects[$p].mcpServers.serena.args[]? // empty' "${cfg}" 2>/dev/null)
    else
        while IFS= read -r a; do args+=("${a}"); done \
            < <(jq -r '.mcpServers.serena.args[]? // empty' "${cfg}" 2>/dev/null)
    fi

    local scope_flag="-s ${scope}"
    claude mcp remove serena ${scope_flag} >/dev/null 2>&1 || true
    if claude mcp add serena ${scope_flag} -- "${serena_bin}" "${args[@]}" >/dev/null 2>&1; then
        [ "${SKILL_EXPLAIN:-0}" = "1" ] && echo "[serena-autoregister] migrated bare reg to ${serena_bin} (${scope})" >&2
    else
        printf '%s\tclaude mcp add failed during abspath migration\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" >"${err}" 2>/dev/null || true
    fi
    : >"${marker}" 2>/dev/null || true
    return 0
}
