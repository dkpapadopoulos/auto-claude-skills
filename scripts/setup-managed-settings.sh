#!/usr/bin/env bash
# setup-managed-settings.sh — Write context-economy defaults into
# ~/.claude/settings.json.
#
# Spec: openspec/changes/context-economy-defaults/specs/context-economy/spec.md
#
# Bare invocation writes truncation defaults (Task A).
# Opt-in flags layer additional behavior:
#   --observability    Task B: OTEL env block
#   --context-hygiene  Task C: .claudeignore template in $PWD
#   --model-routing    Task D: subagent-model + effort presets (default-OFF)
#   --force            Overwrite user-customized values (env-var writes only)
#
# Safety contract:
#   - REFUSES to overwrite an existing settings.json that is not valid JSON
#     (refuses with exit 2; user's file untouched).
#   - REFUSES to modify an `.env` field that is present but not an object.
#   - Tracks per-key write success; emits the "restart Claude" notice only
#     when every write succeeded.
#   - Values are coerced to JSON strings (Claude Code's env contract).
#
# Bash 3.2 compatible. Requires jq.

set -u

FORCE=0
DO_OBSERVABILITY=0
DO_HYGIENE=0
DO_ROUTING=0
WRITE_FAILURES=0

print_help() {
    cat <<'EOF'
Usage: setup-managed-settings.sh [--observability] [--context-hygiene] [--model-routing] [--force] [--help]

Bare: writes truncation defaults (BASH_MAX_OUTPUT_LENGTH=20000,
      MAX_MCP_OUTPUT_TOKENS=10000) into ~/.claude/settings.json env block.

Flags:
  --observability      Also write OTEL env block (CLAUDE_CODE_ENABLE_TELEMETRY,
                       OTEL_METRICS_EXPORTER=otlp, OTEL_LOGS_EXPORTER=otlp).
                       Does NOT set OTEL_EXPORTER_OTLP_ENDPOINT — user-supplied.
  --context-hygiene    Emit .claudeignore in $PWD if absent. Preserves existing.
  --model-routing      Write CLAUDE_CODE_SUBAGENT_MODEL=haiku and
                       CLAUDE_CODE_EFFORT_LEVEL=medium. Overrides per-invocation
                       and frontmatter model/effort for ALL subagents.
                       Default-OFF — see docs/observability.md for probation.
  --force              Overwrite user-customized values for env-var writes.
                       Does NOT affect malformed-JSON or non-object .env
                       safety refusals — those always exit non-zero.
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --observability)    DO_OBSERVABILITY=1; shift ;;
        --context-hygiene)  DO_HYGIENE=1; shift ;;
        --model-routing)    DO_ROUTING=1; shift ;;
        --force)            FORCE=1; shift ;;
        --help|-h)          print_help; exit 0 ;;
        *)                  echo "Unknown arg: $1" >&2; print_help >&2; exit 2 ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required" >&2
    exit 2
fi

SETTINGS="${HOME}/.claude/settings.json"
mkdir -p "$(dirname "${SETTINGS}")"

# Safety: refuse if the file exists but is not writable. `mv` on the wrapper
# directory can succeed even when the target file is chmod 444, so we check
# explicitly before any work.
if [ -f "${SETTINGS}" ] && [ ! -w "${SETTINGS}" ]; then
    echo "ERROR: ${SETTINGS} is not writable (chmod). Refusing to modify." >&2
    echo "       Change file permissions or move it aside before re-running." >&2
    exit 2
fi

# Safety: refuse to overwrite an existing settings.json that is not valid JSON.
# This protects user-set keys (permissions, hooks, mcpServers, etc.) from
# being clobbered if the file was left in a partial state by another tool.
if [ -f "${SETTINGS}" ] && ! jq empty "${SETTINGS}" 2>/dev/null; then
    echo "ERROR: ${SETTINGS} exists but is not valid JSON. Refusing to overwrite." >&2
    echo "       Fix the file manually or move it aside before re-running." >&2
    exit 2
fi

# Create empty object if file is absent.
if [ ! -f "${SETTINGS}" ]; then
    echo '{}' > "${SETTINGS}"
fi

# Safety: refuse if `.env` is present but is not an object.
ENV_TYPE="$(jq -r '.env | type' "${SETTINGS}" 2>/dev/null)"
case "${ENV_TYPE}" in
    object|null)
        : # ok — null means absent; we will initialize to {} on first write.
        ;;
    *)
        echo "ERROR: .env in ${SETTINGS} is ${ENV_TYPE}, expected object." >&2
        echo "       Refusing to reshape user value. Fix .env manually." >&2
        exit 2
        ;;
esac

# write_env_key <key> <value>
# Idempotent: only writes when the key is absent OR --force is set.
# Uses jq has() to distinguish absent from explicitly-empty-string user values.
# Atomic: writes to a tmpfile and renames into place.
write_env_key() {
    local key="$1"
    local value="$2"
    local present
    present="$(jq -r --arg k "${key}" '(.env | type) == "object" and (.env | has($k))' \
        "${SETTINGS}" 2>/dev/null)"

    if [ "${present}" = "true" ] && [ "${FORCE}" -ne 1 ]; then
        local existing
        existing="$(jq -r --arg k "${key}" '.env[$k]' "${SETTINGS}" 2>/dev/null)"
        printf "  preserved user value for %s=%s (use --force to overwrite)\n" \
            "${key}" "${existing}"
        return 0
    fi

    local tmpfile
    tmpfile="${SETTINGS}.tmp.$$"
    if ! jq --arg k "${key}" --arg v "${value}" \
        '.env = (.env // {}) | .env[$k] = $v' "${SETTINGS}" > "${tmpfile}" 2>/dev/null; then
        printf "  FAILED to compute env.%s — jq error\n" "${key}" >&2
        rm -f "${tmpfile}"
        WRITE_FAILURES=$((WRITE_FAILURES + 1))
        return 1
    fi

    if [ ! -s "${tmpfile}" ]; then
        printf "  FAILED to compute env.%s — empty output\n" "${key}" >&2
        rm -f "${tmpfile}"
        WRITE_FAILURES=$((WRITE_FAILURES + 1))
        return 1
    fi

    if ! mv "${tmpfile}" "${SETTINGS}" 2>/dev/null; then
        printf "  FAILED to write env.%s — check permissions on %s\n" \
            "${key}" "${SETTINGS}" >&2
        rm -f "${tmpfile}"
        WRITE_FAILURES=$((WRITE_FAILURES + 1))
        return 1
    fi
    printf "  wrote env.%s=%s\n" "${key}" "${value}"
}

# ---------------------------------------------------------------------------
# Task A — truncation defaults (always run)
# ---------------------------------------------------------------------------
echo "[context-economy] writing truncation defaults"
write_env_key BASH_MAX_OUTPUT_LENGTH 20000
# 10000 is the floor of Anthropic's non-warning range (default 25000, warning
# threshold 10000). NOT the Confluence-suggested 8000 which sits below the
# warning floor.
write_env_key MAX_MCP_OUTPUT_TOKENS 10000

# ---------------------------------------------------------------------------
# Task B — observability preset (opt-in)
# ---------------------------------------------------------------------------
if [ "${DO_OBSERVABILITY}" -eq 1 ]; then
    echo "[context-economy] writing observability preset"
    write_env_key CLAUDE_CODE_ENABLE_TELEMETRY 1
    write_env_key OTEL_METRICS_EXPORTER otlp
    write_env_key OTEL_LOGS_EXPORTER otlp
    echo "  see docs/observability.md for collector setup; OTEL endpoint is user-supplied"
fi

# ---------------------------------------------------------------------------
# Task C — context-hygiene preset (opt-in)
# ---------------------------------------------------------------------------
if [ "${DO_HYGIENE}" -eq 1 ]; then
    echo "[context-economy] writing .claudeignore (if absent)"
    if [ -f ".claudeignore" ]; then
        echo "  preserved existing .claudeignore at $(pwd)"
    else
        if ! cat > .claudeignore <<'CLAUDEIGNORE'
# .claudeignore — keeps Claude Code's auto-discovery out of generated artefacts.
#
# NOTE: .claudeignore is not a security boundary. Claude Code will still read
# files like .env when explicitly asked. For real secret protection, use
# permissions.deny in .claude/settings.json.

node_modules/
dist/
build/
target/
.next/
out/
coverage/
.cache/
.turbo/
.parcel-cache/
__pycache__/
*.pyc
.pytest_cache/
.venv/
venv/
.DS_Store
*.log
CLAUDEIGNORE
        then
            echo "  FAILED to write .claudeignore at $(pwd)" >&2
            WRITE_FAILURES=$((WRITE_FAILURES + 1))
        else
            echo "  wrote .claudeignore at $(pwd)"
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Task D — model-routing preset (opt-in, default-OFF, probation-gated)
# ---------------------------------------------------------------------------
if [ "${DO_ROUTING}" -eq 1 ]; then
    echo "[context-economy] writing model-routing preset"
    echo "  NOTICE: this preset overrides per-invocation model AND subagent"
    echo "  frontmatter — including hard-pinned Opus reviewers. EFFORT_LEVEL"
    echo "  also overrides /effort and frontmatter effort. See"
    echo "  docs/observability.md for probation contract."
    write_env_key CLAUDE_CODE_SUBAGENT_MODEL haiku
    write_env_key CLAUDE_CODE_EFFORT_LEVEL medium
fi

# ---------------------------------------------------------------------------
# Final status: restart notice only when every write succeeded.
# ---------------------------------------------------------------------------
echo ""
if [ "${WRITE_FAILURES}" -gt 0 ]; then
    printf "FAILED: %d env-var write(s) did not complete; see errors above.\n" \
        "${WRITE_FAILURES}" >&2
    echo "no env changes applied — fix the errors and re-run."
    exit 1
fi
echo "restart Claude to apply env-var changes"
