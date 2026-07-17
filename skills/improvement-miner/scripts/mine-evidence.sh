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
    # github-actions is the CORRECT GraphQL author login for gh's `author`
    # field — gh returns it WITHOUT the "[bot]" suffix. Do not "fix" this
    # to "github-actions[bot]"; that value never matches and silently
    # zeroes the eval-report intake (docs use the display form; this is
    # the API form).
    local BOT_LOGIN="github-actions"
    local EVAL_TITLE_PREFIX="Behavioral eval regression"
    # NOTE: field list deliberately excludes comments — trust boundary.
    local raw rc
    raw="$(gh issue list --state all --limit 50 \
            --search "\"${EVAL_TITLE_PREFIX}\" in:title" \
            --json number,title,body,author)"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "ERROR: gh issue list (eval reports) failed with exit ${rc} — improvement-miner is fail-loud, refusing to degrade to an empty bundle (see gh stderr above)" >&2
        exit 5
    fi
    # Guard against empty-but-SUCCESSFUL output (e.g., no matching issues).
    [ -z "${raw}" ] && raw='[]'
    local filtered
    filtered="$(printf '%s' "${raw}" | jq --arg bot "${BOT_LOGIN}" --arg pfx "${EVAL_TITLE_PREFIX}" '[.[] | select((.author.login == $bot) and (.title | startswith($pfx))) | {number, title, body}]')"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "ERROR: eval-report response from gh is not parseable JSON (jq exit ${rc}) — improvement-miner is fail-loud, refusing to degrade to an empty bundle (see jq stderr above)" >&2
        exit 5
    fi
    printf '%s' "${filtered}"
}
LABEL_RUN="improvement-miner-run"

owner_login() {
    # fake-gh in tests ignores --jq and always emits the full JSON object,
    # so extract the login ourselves rather than relying on gh's --jq.
    local raw rc
    raw="$(gh repo view --json owner)"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "ERROR: gh repo view failed with exit ${rc} — improvement-miner is fail-loud, refusing to degrade to an empty ledger (see gh stderr above)" >&2
        exit 5
    fi
    printf '%s' "${raw}" | jq -r '.owner.login // empty' 2>/dev/null
}

json_ledger_items() {
    # Ordered item stream from owner-authored run issues: issues sorted by
    # number ascending, and within each run, items sorted by rank ascending.
    # Output is an ARRAY OF ARRAYS (one inner array per successfully-parsed
    # run issue) — callers that need a flat stream should `flatten` it.
    # Counts must always be derived from these items, never from any
    # embedded counter in the ledger body.
    local owner raw rc
    owner="$(owner_login)"
    rc=$?
    [ "${rc}" -eq 0 ] || exit "${rc}"
    if [ -z "${owner}" ]; then
        echo "ERROR: gh repo view returned no owner login — cannot verify ledger authorship, refusing to degrade to an empty ledger" >&2
        exit 5
    fi
    raw="$(gh issue list --label "${LABEL_RUN}" --state all --limit 200 \
            --json number,body,author)"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "ERROR: gh issue list (ledger) failed with exit ${rc} — improvement-miner is fail-loud, refusing to degrade to an empty ledger (see gh stderr above)" >&2
        exit 5
    fi
    [ -z "${raw}" ] && raw='[]'
    local filtered
    filtered="$(printf '%s' "${raw}" | jq --arg o "${owner}" '
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
        ')"
    rc=$?
    if [ "${rc}" -ne 0 ]; then
        echo "ERROR: ledger response from gh is not parseable JSON (jq exit ${rc}) — the kill criterion cannot be computed from garbage; improvement-miner is fail-loud, refusing to degrade to an empty ledger (see jq stderr above)" >&2
        exit 5
    fi
    printf '%s' "${filtered}"
}

json_ledger_summary() {
    # {runs, presented, approved, items: [ordered flat items], kill}.
    # tripped iff presented >= 5 AND the first 5 chronological items have
    # 0 approved. All counts are derived from `items`, never trusted from
    # any embedded counter in a ledger issue body.
    local items runs rc
    items="$(json_ledger_items)"
    rc=$?
    [ "${rc}" -eq 0 ] || exit "${rc}"
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
    local baselines gate mem evals ledger rc
    baselines="$(json_baselines)"
    gate="$(json_gate_status)"
    mem="$(json_memory_index)"
    # gh-backed sources: capture separately and abort loudly on failure —
    # a swallowed error here must never silently degrade into an
    # empty-looking (falsely "clean") bundle (kill state, dedup).
    evals="$(json_eval_reports)"
    rc=$?
    [ "${rc}" -eq 0 ] || exit "${rc}"
    ledger="$(json_ledger_summary)"
    rc=$?
    [ "${rc}" -eq 0 ] || exit "${rc}"
    jq -n \
        --arg sha "${head_sha}" \
        --argjson baselines "${baselines}" \
        --argjson gate "${gate}" \
        --argjson mem "${mem}" \
        --argjson evals "${evals}" \
        --argjson ledger "${ledger}" \
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
        SUMMARY="$(json_ledger_summary)"
        RC=$?
        [ "${RC}" -eq 0 ] || exit "${RC}"
        ITEMS="$(printf '%s' "${SUMMARY}" | jq '.items')"
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
          def grank: ({"A":1,"B":2,"C":3,"D":4,"F":5}[.grade // ""] // 9);
          . as $in
          | [ $in[] | select(.contract_complete != true)
              | {fp, reason: "missing_contract"} ] as $w1
          | [ $in[] | select(.contract_complete == true) ] as $pool
          | ([ $pool | to_entries[] | select(.value.meta == true) ]
             | sort_by([(.value | grank), .key]) | .[0:2] | [ .[].key ]) as $keepmeta
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
