#!/usr/bin/env bash
# branch-ledger.sh — durable per-(repo+branch) gating-milestone ledger for the
# push gate. Decoupled from the transient composition .completed so gate
# readiness survives composition chain re-anchors. Bash 3.2; all functions
# fail-open: on any error they behave as "no ledger" so the caller falls back
# to the .completed check. Keying mirrors consol-marker.sh (remote-url → path).

branch_ledger_key() {
    local proj_root="${1:-}" key branch sha hash
    [ -z "$proj_root" ] && proj_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proj_root" ] && return 1
    key="$(git -C "$proj_root" remote get-url origin 2>/dev/null || true)"
    [ -z "$key" ] && key="$proj_root"
    branch="$(git -C "$proj_root" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ -z "$branch" ]; then
        sha="$(git -C "$proj_root" rev-parse --short HEAD 2>/dev/null || true)"
        [ -z "$sha" ] && return 1
        branch="detached-${sha}"
    fi
    # shasum (macOS/Perl) may be absent on minimal Linux (Alpine/distroless); fall back to
    # sha1sum — both emit SHA-1, so the key is identical regardless of which tool ran.
    hash="$(printf '%s\x1f%s' "$key" "$branch" | { shasum 2>/dev/null || sha1sum 2>/dev/null; } | cut -d' ' -f1)"
    [ -z "$hash" ] && return 1
    printf '%s' "$hash"
}

branch_ledger_dir() {
    local k; k="$(branch_ledger_key "${1:-}")" || return 1
    [ -z "$k" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-branch-ledger-${k}"
}

branch_ledger_record() {
    local milestone="${1:-}" proj_root="${2:-}" dir sha
    [ -z "$milestone" ] && return 0
    dir="$(branch_ledger_dir "$proj_root")" || return 0
    [ -z "$dir" ] && return 0
    [ -z "$proj_root" ] && proj_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    sha="$(git -C "${proj_root:-.}" rev-parse HEAD 2>/dev/null || true)"
    mkdir -p "$dir" 2>/dev/null || return 0
    # per-milestone file (no shared-JSON read-modify-write → no concurrent race);
    # atomic write; content = "<sha> <utc-ts>"
    printf '%s %s\n' "${sha:-unknown}" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
        > "${dir}/${milestone}.tmp.$$" 2>/dev/null \
        && mv "${dir}/${milestone}.tmp.$$" "${dir}/${milestone}" 2>/dev/null || return 0
    return 0
}

branch_ledger_has() {
    local milestone="${1:-}" proj_root="${2:-}" dir
    [ -z "$milestone" ] && return 1
    dir="$(branch_ledger_dir "$proj_root")" || return 1
    [ -z "$dir" ] && return 1
    [ -f "${dir}/${milestone}" ]
}

branch_ledger_sha() {
    local milestone="${1:-}" proj_root="${2:-}" dir
    dir="$(branch_ledger_dir "$proj_root")" || return 0
    [ -z "$dir" ] && return 0
    [ -f "${dir}/${milestone}" ] || return 0
    cut -d' ' -f1 < "${dir}/${milestone}" 2>/dev/null || true
}

# branch_ledger_bridge_has <milestone> <proj_root> — cross-location read
# (issue #131): 0 iff some SIBLING ledger dir holds <milestone> whose recorded
# SHA is bound to THIS branch — sha == HEAD, or an ancestor of HEAD that is
# NOT reachable from the mainline merge-base (a commit of the branch's local
# segment). Bare ancestor-of-HEAD would over-accept mainline evidence (an old
# main commit is an ancestor of every feature branch), so branch-locality is
# required; if no mainline base resolves, only sha == HEAD bridges. Keys are
# opaque hashes, so the scan needn't know which (repo, branch) a sibling dir
# was for — the SHA binding does all the work (this also covers
# remote-URL-variant key splits). Only called on the gate's would-deny path.
# On success prints the matched SHA (for the caller's advisory).
# Fail-open as "no bridge": the bridge can rescue, never deny.
branch_ledger_bridge_has() {
    local milestone="${1:-}" proj_root="${2:-}" own="" head base="" ref d f sha
    [ -z "$milestone" ] && return 1
    case "$milestone" in */*|*..*) return 1 ;; esac   # path-safe: milestone is a filename
    [ -z "$proj_root" ] && proj_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proj_root" ] && return 1
    head="$(git -C "$proj_root" rev-parse HEAD 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    own="$(branch_ledger_dir "$proj_root")" || own=""
    # Mainline names first; '@{upstream}' LAST — for a feature branch the
    # upstream is normally origin/<itself> (git push -u), so consulting it
    # before mainline refs would set base to the branch's own pushed tip and
    # exclude legitimately branch-local commits (review finding, U7).
    for ref in origin/HEAD origin/main main origin/master master '@{upstream}'; do
        base="$(git -C "$proj_root" merge-base HEAD "$ref" 2>/dev/null)" && [ -n "$base" ] && break
        base=""
    done
    for d in "${HOME}/.claude/.skill-branch-ledger-"*; do
        [ -d "$d" ] || continue
        [ -n "$own" ] && [ "$d" = "$own" ] && continue
        f="${d}/${milestone}"
        [ -f "$f" ] || continue
        sha="$(cut -d' ' -f1 < "$f" 2>/dev/null)" || continue
        [ -n "$sha" ] || continue
        [ "$sha" = "$head" ] && { printf '%s' "$sha"; return 0; }
        [ -n "$base" ] || continue                    # no mainline base => exact-HEAD only
        [ "$sha" = "$base" ] && continue              # the base itself is mainline
        git -C "$proj_root" merge-base --is-ancestor "$sha" "$head" 2>/dev/null || continue
        git -C "$proj_root" merge-base --is-ancestor "$sha" "$base" 2>/dev/null && continue
        printf '%s' "$sha"
        return 0
    done
    return 1
}
