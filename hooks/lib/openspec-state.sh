#!/usr/bin/env bash
# openspec-state.sh — Persistence helper for OpenSpec session state
# Sourced by skills/hooks that need state file access.
# Bash 3.2 compatible. Requires jq.

# State file path: ~/.claude/.skill-openspec-state-<session_token>

# --- openspec_state_mark_verified <session_token> <surface> -------
# Create or update state file with verification fields.
# Idempotent merge: preserves existing 'changes' map.
openspec_state_mark_verified() {
    local token="${1:-}"
    local surface="${2:-none}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    if [ -f "$state_file" ]; then
        # Merge into existing file
        local tmp
        tmp="$(jq --arg surface "$surface" --arg now "$now" '
            .verification_seen = true |
            .verification_at = $now |
            .openspec_surface = (.openspec_surface // $surface)
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file
        jq -n --arg surface "$surface" --arg now "$now" '{
            openspec_surface: $surface,
            verification_seen: true,
            verification_at: $now,
            changes: {}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_upsert_change <token> <slug> <plan_path> <spec_path> <capability> [<design_path>] ---
# Add or update a change entry in the changes map.
# Idempotent: existing entries for other slugs are preserved.
# Writes canonical field names (design_path, plan_path, spec_path) and
# legacy aliases (sp_plan_path, sp_spec_path) for backward compatibility.
openspec_state_upsert_change() {
    local token="${1:-}"
    local slug="${2:-}"
    local plan_path="${3:-}"
    local spec_path="${4:-}"
    local capability="${5:-}"
    local design_path="${6:-}"
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping state write" >&2 && return 0
    [ -z "$slug" ] && echo "[openspec-state] WARN: no change slug, skipping state write" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" --arg dp "$design_path" '
            .changes[$slug] = ((.changes[$slug] // {}) + {
                design_path: (if $dp == "" then (.changes[$slug].design_path // null) else $dp end),
                plan_path: (if $pp == "" then (.changes[$slug].plan_path // null) else $pp end),
                spec_path: (if $sp == "" then (.changes[$slug].spec_path // null) else $sp end),
                sp_plan_path: (if $pp == "" then (.changes[$slug].sp_plan_path // null) else $pp end),
                sp_spec_path: (if $sp == "" then (.changes[$slug].sp_spec_path // null) else $sp end),
                capability_slug: (if $cap == "" then (.changes[$slug].capability_slug // null) else $cap end),
                archived_at: (.changes[$slug].archived_at // null)
            })
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        # Create new file with just the change entry
        jq -n --arg slug "$slug" --arg pp "$plan_path" --arg sp "$spec_path" --arg cap "$capability" --arg dp "$design_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {
                design_path: $dp,
                plan_path: $pp,
                spec_path: $sp,
                sp_plan_path: $pp,
                sp_spec_path: $sp,
                capability_slug: $cap,
                archived_at: null
            }}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_set_discovery_path <token> <slug> <discovery_path> ---
# Set discovery_path for a change entry.
# Creates the change entry if it doesn't exist (merges with existing fields).
# Same jq-merge pattern as openspec_state_mark_verified.
openspec_state_set_discovery_path() {
    local token="${1:-}"
    local slug="${2:-}"
    local discovery_path="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg dp "$discovery_path" '
            .changes[$slug] = ((.changes[$slug] // {}) + {discovery_path: $dp})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --arg dp "$discovery_path" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {discovery_path: $dp}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_set_intent <token> <intent_text> --------------
# Persist a confirmed-intent statement to a flat marker file
# ~/.claude/.skill-confirmed-intent-<token>. Captured pre-design
# (before a change slug exists), so it is NOT stored in the openspec
# state JSON. Existence = suppression signal for the intent-extraction
# directive; contents feed the brainstorming handoff. Overwrites.
# No-op on empty token or empty text.
openspec_state_set_intent() {
    local token="${1:-}"
    local intent="${2:-}"
    [ -z "$token" ] && return 0
    [ -z "$intent" ] && return 0
    local f="${HOME}/.claude/.skill-confirmed-intent-${token}"
    printf '%s\n' "$intent" > "$f" 2>/dev/null || return 0
}

# --- openspec_state_read_intent <token> ---------------------------
# Print the confirmed-intent marker contents (single line) or nothing.
# No-op on empty token or missing file.
openspec_state_read_intent() {
    local token="${1:-}"
    [ -z "$token" ] && return 0
    local f="${HOME}/.claude/.skill-confirmed-intent-${token}"
    [ -f "$f" ] || return 0
    head -1 "$f" 2>/dev/null || return 0
}

# --- openspec_state_set_hypotheses <token> <slug> <hypotheses_json> ---
# Set hypotheses array for a change entry. Validates input is JSON.
# Creates change entry if absent; merges into existing fields otherwise.
# No-op on empty token/slug/json or invalid JSON.
openspec_state_set_hypotheses() {
    local token="${1:-}"
    local slug="${2:-}"
    local hyps_json="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0
    [ -z "$hyps_json" ] && return 0

    # Validate shape: must be a JSON array (outcome-review iterates as list)
    printf '%s' "$hyps_json" | jq -e 'type == "array"' >/dev/null 2>&1 || return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --argjson hyps "$hyps_json" '
            .changes[$slug] = ((.changes[$slug] // {}) + {hypotheses: $hyps})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --argjson hyps "$hyps_json" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {hypotheses: $hyps}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_mark_archived <token> <slug> [<timestamp>] ----
# Mark a change as archived (shipped) in session state. Sets archived_at
# so write_learn_baseline can capture the real ship time instead of
# falling back to the stop-hook wall-clock time.
# Called from openspec-ship after archival completes.
openspec_state_mark_archived() {
    local token="${1:-}"
    local slug="${2:-}"
    local ts="${3:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0
    [ -z "$ts" ] && ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"

    if [ -f "$state_file" ]; then
        local tmp
        tmp="$(jq --arg slug "$slug" --arg ts "$ts" '
            .changes[$slug] = ((.changes[$slug] // {}) + {archived_at: $ts})
        ' "$state_file" 2>/dev/null)" || return 0
        printf '%s\n' "$tmp" > "$state_file"
    else
        jq -n --arg slug "$slug" --arg ts "$ts" '{
            openspec_surface: "none",
            verification_seen: false,
            verification_at: null,
            changes: {($slug): {archived_at: $ts}}
        }' > "$state_file" 2>/dev/null || return 0
    fi
}

# --- openspec_state_write_learn_baseline <token> <slug> -----------
# Write ~/.claude/.skill-learn-baselines/<slug>.json for outcome-review to read.
# Skips silently when:
#   - state file or change entry is missing
#   - hypotheses are null or empty (no loop to close)
#   - no ship signal: neither archived_at in state nor openspec/changes/archive/<slug>/
# Detects ship_method via gh PR lookup → pull_request; main/master branch → merge.
# Extracts jira_ticket from discovery file if present.
openspec_state_write_learn_baseline() {
    local token="${1:-}"
    local slug="${2:-}"
    [ -z "$token" ] && return 0
    [ -z "$slug" ] && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    [ -f "$state_file" ] || return 0

    local hyps
    hyps="$(jq -c --arg slug "$slug" '.changes[$slug].hypotheses // null' "$state_file" 2>/dev/null)"
    [ -z "$hyps" ] && return 0
    [ "$hyps" = "null" ] && return 0
    [ "$hyps" = "[]" ] && return 0

    local proj_root
    proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

    local archived_at
    archived_at="$(jq -r --arg slug "$slug" '.changes[$slug].archived_at // empty' "$state_file" 2>/dev/null)"

    local shipped="false"
    if [ -n "$archived_at" ] && [ "$archived_at" != "null" ]; then
        shipped="true"
    elif [ -d "${proj_root}/openspec/changes/archive/${slug}" ]; then
        shipped="true"
    fi
    [ "$shipped" = "false" ] && return 0

    local shipped_at
    if [ -n "$archived_at" ] && [ "$archived_at" != "null" ]; then
        shipped_at="$archived_at"
    else
        shipped_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

    local branch
    branch="$(git -C "$proj_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    # Detached HEAD returns literal "HEAD" — substitute short SHA for clarity
    if [ "$branch" = "HEAD" ]; then
        branch="$(git -C "$proj_root" rev-parse --short HEAD 2>/dev/null || echo 'detached')"
    fi

    local ship_method="unknown"
    local pr_url=""
    if command -v gh >/dev/null 2>&1; then
        # Scope gh to $proj_root so it resolves the right repo regardless of cwd
        pr_url="$(cd "$proj_root" 2>/dev/null && gh pr view "$branch" --json url -q .url 2>/dev/null || true)"
        [ -n "$pr_url" ] && ship_method="pull_request"
    fi
    if [ "$ship_method" = "unknown" ]; then
        case "$branch" in
            main|master) ship_method="merge" ;;
        esac
    fi

    local discovery_path
    discovery_path="$(jq -r --arg slug "$slug" '.changes[$slug].discovery_path // empty' "$state_file" 2>/dev/null)"

    local jira_ticket=""
    if [ -n "$discovery_path" ]; then
        local disc_abs="${discovery_path}"
        case "$disc_abs" in
            /*) ;;
            *) disc_abs="${proj_root}/${discovery_path}" ;;
        esac
        if [ -f "$disc_abs" ]; then
            # Jira shape: 2-10 uppercase letters, hyphen, 2+ digits (rules out
            # HTTP-2, UTF-8). Denylist filters common technical standards that
            # share the shape (SHA-256, ISO-8601, OAUTH-2, CVE-2024-xxxx, etc.)
            # so they don't win when they appear earlier in the doc than the
            # real ticket.
            jira_ticket="$(grep -oE '[A-Z]{2,10}-[0-9]{2,}' "$disc_abs" 2>/dev/null \
                | grep -vE '^(SHA|ISO|UTF|HTTP|OAUTH|ASCII|UUID|RSA|CVE|RFC|MD|TLS|SSL|SSH|DNS|XML|JSON|HTML|CSS|SMTP|IMAP|TCP|UDP|HMAC|JWT|SAML|OIDC|GDPR|HIPAA|SOC|IPV|IPv)-' \
                | head -1 || true)"
        fi
    fi

    local baseline_dir="${HOME}/.claude/.skill-learn-baselines"
    mkdir -p "$baseline_dir" 2>/dev/null || return 0
    local baseline_file="${baseline_dir}/${slug}.json"

    jq -n \
        --arg slug "$slug" \
        --arg branch "$branch" \
        --arg shipped_at "$shipped_at" \
        --arg ship_method "$ship_method" \
        --arg pr_url "$pr_url" \
        --arg jira "$jira_ticket" \
        --arg discovery "$discovery_path" \
        --argjson hyps "$hyps" \
        '{
            schema_version: 1,
            slug: $slug,
            branch: $branch,
            shipped_at: $shipped_at,
            ship_method: $ship_method,
            pr_url: (if $pr_url == "" then null else $pr_url end),
            jira_ticket: (if $jira == "" then null else $jira end),
            discovery_path: (if $discovery == "" then null else $discovery end),
            hypotheses: $hyps
        }' > "$baseline_file" 2>/dev/null || return 0
}

# --- openspec_state_read <session_token> --------------------------
# Read and output current state file as JSON.
# Returns empty {} if file doesn't exist or is malformed.
openspec_state_read() {
    local token="${1:-}"
    [ -z "$token" ] && echo '{}' && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    if [ -f "$state_file" ]; then
        jq '.' "$state_file" 2>/dev/null || echo '{}'
    else
        echo '{}'
    fi
}

# --- openspec_write_provenance <archive_path> <session_token> <slug> ---
# Write source.json to <archive_path>/superpowers/source.json.
# Creates the superpowers/ directory if needed.
openspec_write_provenance() {
    local archive_path="${1:-}"
    local token="${2:-}"
    local slug="${3:-}"
    [ -z "$archive_path" ] && echo "[openspec-state] WARN: no archive path, skipping provenance" >&2 && return 0
    [ -z "$token" ] && echo "[openspec-state] WARN: no session token, skipping provenance" >&2 && return 0

    local state_file="${HOME}/.claude/.skill-openspec-state-${token}"
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
    local commit
    commit="$(git rev-parse HEAD 2>/dev/null || echo 'unknown')"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    mkdir -p "${archive_path}/superpowers"

    if [ -f "$state_file" ] && [ -n "$slug" ]; then
        jq --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '
            {
                schema_version: 1,
                discovery_path: (.changes[$slug].discovery_path // null),
                design_path: (.changes[$slug].design_path // null),
                plan_path: (.changes[$slug].plan_path // .changes[$slug].sp_plan_path // null),
                spec_path: (.changes[$slug].spec_path // .changes[$slug].sp_spec_path // null),
                # Legacy aliases (deprecated — readers should use canonical names above)
                sp_plan_path: (.changes[$slug].sp_plan_path // .changes[$slug].plan_path // null),
                sp_spec_path: (.changes[$slug].sp_spec_path // .changes[$slug].spec_path // null),
                change_slug: $slug,
                capability_slug: (.changes[$slug].capability_slug // null),
                source_branch: $branch,
                base_commit: $commit,
                openspec_surface: (.openspec_surface // "none"),
                archived_at: $now
            }
        ' "$state_file" > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    else
        # No state file — write minimal provenance
        jq -n --arg slug "$slug" --arg branch "$branch" --arg commit "$commit" --arg now "$now" '{
            schema_version: 1,
            discovery_path: null,
            design_path: null,
            plan_path: null,
            spec_path: null,
            sp_plan_path: null,
            sp_spec_path: null,
            change_slug: $slug,
            capability_slug: null,
            source_branch: $branch,
            base_commit: $commit,
            openspec_surface: "none",
            archived_at: $now
        }' > "${archive_path}/superpowers/source.json" 2>/dev/null || {
            echo "[openspec-state] WARN: provenance write failed" >&2
            return 0
        }
    fi
}
