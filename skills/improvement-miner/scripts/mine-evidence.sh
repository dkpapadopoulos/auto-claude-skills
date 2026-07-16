#!/bin/bash
# mine-evidence.sh — deterministic evidence collector for the
# improvement-miner skill (Stage 1 LEARN miner).
#
# Modes:
#   fingerprint <class> <id>   print 16-hex fingerprint of class:id
#   bundle                     print JSON evidence bundle on stdout
#   dedup <fp>...              print prior decision per fingerprint
#   select                     stdin: candidate JSON array -> gated selection
#
# FAIL-LOUD BY DESIGN: this is a user-invoked tool, not a fail-open hook.
# Trust boundary lives HERE, not in skill prose: author allowlist, no
# comments, no raw artifact fields, no tests/fixtures/*/evals content.
set -u

MODE="${1:-}"

usage() {
    echo "usage: mine-evidence.sh fingerprint <class> <id> | bundle | dedup <fp>... | select" >&2
    exit 2
}

require() {
    command -v "$1" >/dev/null 2>&1 && return 0
    echo "ERROR: required tool '$1' not found (improvement-miner is fail-loud)" >&2
    exit 3
}

fp_of() { printf '%s:%s' "$1" "$2" | shasum -a 256 | cut -c1-16; }

main_repo_root() {
    # physical main checkout root (worktree-safe): common gitdir's parent
    local common; common="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
    ( cd "$(dirname "${common}")" && pwd -P )
}

memory_dir() {
    if [ -n "${IMPROVEMENT_MINER_MEMORY_DIR:-}" ]; then
        printf '%s' "${IMPROVEMENT_MINER_MEMORY_DIR}"; return
    fi
    local root slug
    root="$(main_repo_root)" || { printf ''; return; }
    slug="$(printf '%s' "${root}" | sed 's|[/.]|-|g')"
    printf '%s' "${HOME}/.claude/projects/${slug}/memory"
}

json_baselines() {
    ls tests/baselines/*.baseline.json 2>/dev/null \
        | jq -R . | jq -s 'map(select(length > 0))'
}

json_gate_status() {
    if [ -f scripts/gate-status.sh ]; then
        local out; out="$(/bin/bash scripts/gate-status.sh 2>&1 || true)"
        jq -n --arg o "${out}" '{available: true, output: $o}'
    else
        jq -n '{available: false, output: ""}'
    fi
}

json_memory_index() {
    local dir; dir="$(memory_dir)"
    [ -d "${dir}" ] || { echo '[]'; return; }
    local f base name desc kind rows
    rows='[]'
    for f in "${dir}"/*.md; do
        [ -f "${f}" ] || continue
        base="$(basename "${f}")"
        [ "${base}" = "MEMORY.md" ] && continue
        name="$(grep -m1 '^name:' "${f}" | sed 's/^name:[[:space:]]*//')"
        desc="$(grep -m1 '^description:' "${f}" | sed 's/^description:[[:space:]]*//')"
        kind=""
        case "${base}" in feedback_*) kind="feedback" ;; esac
        if [ -z "${kind}" ] && grep -qi 'revival' "${f}"; then kind="revival"; fi
        [ -z "${kind}" ] && continue
        rows="$(printf '%s' "${rows}" | jq --arg f "${base}" --arg n "${name}" \
            --arg d "${desc}" --arg k "${kind}" '. + [{file:$f,name:$n,description:$d,kind:$k}]')"
    done
    printf '%s' "${rows}"
}

json_eval_reports() {
    local BOT_LOGIN="github-actions"
    local EVAL_TITLE_PREFIX="Behavioral eval regression"
    # NOTE: field list deliberately excludes comments — trust boundary.
    local raw
    raw="$(gh issue list --state all --limit 50 \
            --search "\"${EVAL_TITLE_PREFIX}\" in:title" \
            --json number,title,body,author 2>/dev/null)" || raw='[]'
    # Guard against empty output (e.g., from testing fixtures)
    [ -z "${raw}" ] && raw='[]'
    printf '%s' "${raw}" | jq --arg bot "${BOT_LOGIN}" --arg pfx "${EVAL_TITLE_PREFIX}" '[.[] | select((.author.login == $bot) and (.title | startswith($pfx))) | {number, title, body}]' 2>/dev/null || echo '[]'
}
json_ledger_summary() { echo '{}'; }

emit_bundle() {
    local head_sha; head_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    jq -n \
        --arg sha "${head_sha}" \
        --argjson baselines "$(json_baselines)" \
        --argjson gate "$(json_gate_status)" \
        --argjson mem "$(json_memory_index)" \
        --argjson evals "$(json_eval_reports)" \
        --argjson ledger "$(json_ledger_summary)" \
        '{schema: 1, head_sha: $sha, baselines: $baselines, gate_status: $gate,
          memory_index: $mem, eval_reports: $evals, ledger: $ledger,
          kill: ($ledger.kill // {})}'
}

case "${MODE}" in
    fingerprint)
        require shasum
        [ -n "${2:-}" ] && [ -n "${3:-}" ] || usage
        fp_of "$2" "$3"
        ;;
    bundle)
        require jq; require gh; require shasum
        REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || { echo "ERROR: not a git repository" >&2; exit 2; }
        cd "${REPO_ROOT}" || exit 2
        emit_bundle
        ;;
    dedup|select)
        require jq; require gh; require shasum
        echo "ERROR: mode '${MODE}' not implemented yet" >&2
        exit 4
        ;;
    *) usage ;;
esac
