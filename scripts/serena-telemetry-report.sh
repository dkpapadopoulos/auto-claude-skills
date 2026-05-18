#!/usr/bin/env bash
# serena-telemetry-report.sh — Summarise follow-through % per matcher class
# from ~/.claude/.serena-nudge-telemetry over a rolling window (default 14 days).
#
# Usage: bash scripts/serena-telemetry-report.sh [days]
set -u

DAYS="${1:-14}"
TELEM="${HOME}/.claude/.serena-nudge-telemetry"

if [ ! -s "${TELEM}" ]; then
    echo "no telemetry recorded yet at ${TELEM}"
    exit 0
fi

NOW="$(date +%s)"
WINDOW=$((DAYS * 86400))
CUTOFF=$((NOW - WINDOW))

awk -F'\t' -v cutoff="${CUTOFF}" '
$1 >= cutoff {
    kind = $4; cls = $5; tok = $2; turn = $3;
    if (kind == "nudge" || kind == "observe") {
        # Dedupe by (token, turn, class) so multiple firings within the same
        # turn count once. The follow-through correlator records at most one
        # followup per (turn, class) pair, so the denominator must match.
        key = tok "\x01" turn "\x01" cls;
        if (!(key in firing_seen)) {
            firing_seen[key] = 1;
            firings[cls]++;
            if (!(cls in seen)) { seen[cls] = 1; order[++ord] = cls; }
        }
    } else if (kind == "followup") {
        followups[cls]++;
        followup_tool[$6]++;
    }
}
END {
    if (ord == 0) {
        print "no firings in window";
    } else {
        printf "%-25s %8s %10s %12s\n", "class", "firings", "followups", "pct";
        for (i = 1; i <= ord; i++) {
            cls = order[i];
            n = firings[cls];
            f = (cls in followups) ? followups[cls] : 0;
            pct = (n > 0) ? int((f * 100) / n) : 0;
            printf "%-25s %8d %10d %11d%%\n", cls, n, f, pct;
        }
    }

    # --- v1.3.0 adoption ---
    # Counts per-tool usage among followups for the four v1.3.0 tools, plus a
    # composite "v1.3.0 share": % of recent find_*/diagnostics followups that
    # use v1.3.0 names vs legacy names.
    n_decl  = followup_tool["find_declaration"]         + 0;
    n_impl  = followup_tool["find_implementations"]     + 0;
    n_dfile = followup_tool["get_diagnostics_for_file"] + 0;
    n_dsym  = followup_tool["get_diagnostics_for_symbol"] + 0;
    v13_total = n_decl + n_impl + n_dfile + n_dsym;

    legacy_total = followup_tool["find_symbol"]              + 0 \
                 + followup_tool["find_referencing_symbols"] + 0 \
                 + followup_tool["get_symbols_overview"]     + 0 \
                 + followup_tool["insert_after_symbol"]      + 0 \
                 + followup_tool["replace_symbol_body"]      + 0 \
                 + followup_tool["rename_symbol"]            + 0;

    denom = v13_total + legacy_total;
    share = (denom > 0) ? int((v13_total * 100) / denom) : 0;

    print "";
    print "### v1.3.0 adoption";
    printf "  %-27s %d\n", "find_declaration:",          n_decl;
    printf "  %-27s %d\n", "find_implementations:",      n_impl;
    printf "  %-27s %d\n", "get_diagnostics_for_file:",  n_dfile;
    printf "  %-27s %d\n", "get_diagnostics_for_symbol:", n_dsym;
    print  "  ---";
    printf "  %-27s %d\n",  "v1.3.0 total:", v13_total;
    printf "  %-27s %d\n",  "legacy total:", legacy_total;
    printf "  %-27s %d%%\n", "v1.3.0 share:", share;
}' "${TELEM}"
