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
LABEL_RUN="improvement-miner-run"

owner_login() {
    # fake-gh in tests ignores --jq and always emits the full JSON object,
    # so extract the login ourselves rather than relying on gh's --jq.
    gh repo view --json owner 2>/dev/null | jq -r '.owner.login // empty' 2>/dev/null
}

json_ledger_items() {
    # Ordered item stream from owner-authored run issues: issues sorted by
    # number ascending, and within each run, items sorted by rank ascending.
    # Output is an ARRAY OF ARRAYS (one inner array per successfully-parsed
    # run issue) — callers that need a flat stream should `flatten` it.
    # Counts must always be derived from these items, never from any
    # embedded counter in the ledger body.
    local owner raw
    owner="$(owner_login)"
    [ -n "${owner}" ] || { echo '[]'; return; }
    raw="$(gh issue list --label "${LABEL_RUN}" --state all --limit 200 \
            --json number,body,author 2>/dev/null)" || raw='[]'
    [ -z "${raw}" ] && raw='[]'
    printf '%s' "${raw}" | jq --arg o "${owner}" '
        [ .[] | select(.author.login == $o) ]
        | sort_by(.number)
        | map(
            (.body
             | split("```json")
             | (if length > 1 then .[1] else "" end)
             | split("```")
             | (.[0] // "")) as $j
            | ($j | try fromjson catch null) as $run
            | select($run != null)
            | ($run.presented // []) | sort_by(.rank)
          )
        ' 2>/dev/null || echo '[]'
}

json_ledger_summary() {
    # {runs, presented, approved, items: [ordered flat items], kill}.
    # tripped iff presented >= 5 AND the first 5 chronological items have
    # 0 approved. All counts are derived from `items`, never trusted from
    # any embedded counter in a ledger issue body.
    local items runs
    items="$(json_ledger_items)"
    runs="$(printf '%s' "${items}" | jq 'length')"
    printf '%s' "${items}" | jq --argjson runs "${runs}" '
        flatten as $flat
        | ($flat | length) as $presented
        | ([ $flat[] | select(.decision == "approved") ] | length) as $approved
        | ([ $flat[0:5][] | select(.decision == "approved") ] | length) as $first5
        | {runs: $runs, presented: $presented, approved: $approved,
           items: $flat,
           kill: {state: (if $presented >= 5 and $first5 == 0
                          then "tripped" else "alive" end),
                  presented: $presented, approved: $approved}}'
}

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
    dedup)
        require jq; require gh; require shasum
        REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || { echo "ERROR: not a git repository" >&2; exit 2; }
        cd "${REPO_ROOT}" || exit 2
        shift
        [ "$#" -ge 1 ] || usage
        ITEMS="$(json_ledger_summary | jq '.items')"
        for f in "$@"; do
            printf '%s' "${ITEMS}" | jq -r --arg fp "${f}" '
                [ .[] | select(.fp == $fp) ] as $m
                | if ($m | length) == 0 then "\($fp) new"
                  elif ($m[-1].decision == "approved") then "\($fp) approved \($m[-1].issue)"
                  else "\($fp) rejected" end'
        done
        ;;
    select)
        require jq
        jq '
          def grank: {"A":1,"B":2,"C":3,"D":4,"F":5}[.grade] // 9;
          . as $in
          | [ $in[] | select(.contract_complete != true)
              | {fp, reason: "missing_contract"} ] as $w1
          | [ $in[] | select(.contract_complete == true) ] as $pool
          | ([ $pool | to_entries[] | select(.value.meta == true) ]
             | sort_by([.value | grank, .key]) | .[0:2] | [ .[].key ]) as $keepmeta
          | [ $pool | to_entries[]
              | select(.value.meta != true or (.key as $k | $keepmeta | index($k) != null))
              | .value ] as $afterMeta
          | [ $pool | to_entries[]
              | select(.value.meta == true and (.key as $k | $keepmeta | index($k) == null))
              | {fp: .value.fp, reason: "meta_cap"} ] as $w2
          | ($afterMeta | .[0:5]) as $presented
          | [ $afterMeta | .[5:][] | {fp, reason: "cap"} ] as $w3
          | {presented: $presented,
             withheld: ($w1 + $w2 + $w3),
             warnings: (if ([ $presented[] | select(.end_user == true) ] | length) == 0
                        then ["no_end_user_facing"] else [] end)}'
        ;;

    *) usage ;;
esac
