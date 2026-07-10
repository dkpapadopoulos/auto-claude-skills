#!/bin/bash
# assumption-audit-check.sh — deterministic evidence-ceiling check for the
# Assumption Ledger emitted by skills/product-discovery.
#
# Usage: assumption-audit-check.sh <discovery-doc.md>
# Exit 0: pass, or fail-open (missing arg/file).
# Exit 1: one or more VIOLATION lines printed to stdout.
#
# Bash 3.2 compatible. No jq. No set -e.

DOC="${1:-}"
if [ -z "$DOC" ] || [ ! -f "$DOC" ]; then
    echo "[assumption-audit] no readable doc (${DOC:-<none>}) — skipping (fail-open)" >&2
    exit 0
fi

VIOLATIONS=0
violate() { echo "VIOLATION: $1"; VIOLATIONS=$((VIOLATIONS + 1)); }

# grade/ceiling ranks: A=1 (best) .. F=5
grade_rank() {
    case "$1" in
        A) echo 1 ;; B) echo 2 ;; C) echo 3 ;; D) echo 4 ;; F) echo 5 ;;
        *) echo 0 ;;
    esac
}
kind_ceiling() {
    case "$1" in
        direct_metric|direct_observation) echo 1 ;;
        analogous) echo 3 ;;
        expert_judgment) echo 4 ;;
        none) echo 5 ;;
        *) echo 0 ;;
    esac
}

# Extract the ledger section (from '## Assumption Ledger' to next '## ').
LEDGER="$(awk '/^## Assumption Ledger/{f=1;next} /^## /{f=0} f' "$DOC")"
if [ -z "$LEDGER" ]; then
    violate "missing '## Assumption Ledger' section"
else
    # Table rows: lines starting with '|', skipping header and separator.
    # Route rows through a temp file (not a pipe) so the row loop runs in the
    # main shell, not a subshell — VIOLATIONS increments must survive it.
    ROWS_FILE="$(mktemp "${TMPDIR:-/tmp}/assumption-audit-rows.XXXXXX")"
    trap 'rm -f "$ROWS_FILE"' EXIT
    printf '%s\n' "$LEDGER" | grep '^|' | grep -v '^| *id *|' | grep -v '^|[-| ]*$' > "$ROWS_FILE"

    while IFS= read -r row; do
        [ -z "$row" ] && continue
        # awk field 1 is empty (leading '|'); trim spaces per field.
        aid="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')"
        importance="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')"
        kind="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}')"
        sref="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$7); print $7}')"
        seen="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$8); print $8}')"
        grade="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$9); print $9}')"
        thresh="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$10); print $10}')"
        [ -z "$aid" ] && continue

        g="$(grade_rank "$grade")"; c="$(kind_ceiling "$kind")"
        if [ "$g" -eq 0 ]; then violate "$aid: unknown grade '$grade'"; continue; fi
        if [ "$c" -eq 0 ]; then violate "$aid: unknown evidence_kind '$kind'"; continue; fi
        if [ "$g" -lt "$c" ]; then
            violate "$aid: grade $grade exceeds evidence ceiling for $kind (evidence-ceiling rule)"
        fi
        if [ "$g" -le 2 ]; then   # A or B
            [ -z "$sref" ] && violate "$aid: grade $grade requires source_ref"
            [ -z "$seen" ] && violate "$aid: grade $grade requires observed_at"
            case "$sref" in
                *#*)
                    p="${sref%%#*}"; lit="${sref#*#}"
                    if [ -f "$p" ]; then
                        grep -qF "$lit" "$p" 2>/dev/null \
                            || violate "$aid: source_ref literal not found in $p"
                    fi
                    ;;
            esac
        fi
        # Case-insensitive: h/H/high/High all count — lowercase must not
        # silently bypass the fragile-threshold rule (false-PASS direction).
        _imp_uc="$(printf '%s' "$importance" | tr '[:lower:]' '[:upper:]')"
        case "$_imp_uc" in H|HIGH) _imp_high=1 ;; *) _imp_high=0 ;; esac
        if [ "$_imp_high" -eq 1 ] && [ "$g" -ge 3 ]; then  # fragile
            [ -z "$thresh" ] && violate "$aid: fragile assumption missing kill_threshold (use 'untested (cutoff)' below the materiality cutoff)"
        fi
    done < "$ROWS_FILE"

    rm -f "$ROWS_FILE"
    trap - EXIT
fi

# Options section must include a do-nothing baseline.
if ! awk '/^## Options/{f=1;next} /^## /{f=0} f' "$DOC" | grep -qi 'do.nothing'; then
    violate "Options section missing a do-nothing baseline row"
fi

if [ "$VIOLATIONS" -gt 0 ]; then
    echo "[assumption-audit] ${VIOLATIONS} violation(s) in ${DOC}" >&2
    exit 1
fi
echo "[assumption-audit] OK: ${DOC}" >&2
exit 0
