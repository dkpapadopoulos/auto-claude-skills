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
    local add_output add_rc
    add_output="$(claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd --open-web-dashboard false 2>&1)"
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
