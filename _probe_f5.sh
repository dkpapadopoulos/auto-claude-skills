#!/usr/bin/env bash
# Discharge probe for #254 d2. NOT a shipped test — measurement instrument.
set -u
ROOT="/private/tmp/acs-254-d2"
GUARD="${ROOT}/hooks/openspec-guard.sh"

export HOME="$(mktemp -d /tmp/f5-home-XXXXXX)"
mkdir -p "$HOME/.claude"
TP="$HOME/t.jsonl"; touch "$TP"; TOK="session-t"
COMP="$HOME/.claude/.skill-composition-state-${TOK}"
VERD="$HOME/.claude/.skill-project-verified-${TOK}"
HEAD_SHA="$(git -C "$ROOT" rev-parse HEAD)"

# Chain: REVIEW completed, VERIFY in chain and NOT completed -> Check 2 must fire.
mk_comp() {
  jq -nc --argjson c '["requesting-code-review","verification-before-completion"]' \
         --argjson d '["requesting-code-review"]' \
         '{chain:$c,current_index:1,completed:$d}' > "$COMP"
}
mk_comp

mkinput() { jq -n --arg tp "$TP" --arg cmd "${1:-git push origin HEAD}" \
  '{"transcript_path":$tp,"tool_input":{"command":$cmd}}'; }
run() { local g="${2:-$GUARD}"; mkinput "${1:-}" | CLAUDE_PLUGIN_ROOT="$ROOT" bash "$g" 2>/dev/null; }

say() { printf '%s\n' "$*"; }
verdict_of() {  # classify guard output
  case "$1" in
    *'"deny"'*) printf 'DENY';;
    '') printf 'EMPTY';;
    *) printf 'ALLOW';;
  esac
}
which_gate() {
  case "$1" in
    *"verification-before-completion completed before push"*) printf 'chain-verify';;
    *"requesting-code-review completed before"*)             printf 'chain-review';;
    *"routing governance"*)                                   printf 'routing-governance';;
    *"fail-closed"*)                                          printf 'global-failclosed';;
    *"failing gate"*)                                         printf 'verify-hardening';;
    *"DESIGN"*|*"phase"*)                                     printf 'phase-enforcement';;
    *'"deny"'*)                                               printf 'deny-other';;
    *)                                                        printf 'n/a';;
  esac
}

say "### PRECONDITION: which gate denies, with the falsifier PRESENT"
jq -nc --arg s "$HEAD_SHA" '{sha:$s,gate_gaming_status:"clean"}' > "$VERD"
say "    falsifier artifact: $(cat "$VERD")"
out="$(run)"
say "    current guard      -> $(verdict_of "$out") / $(which_gate "$out")"

say ""
say "### Is the minimal artifact accepted by the predicate the global leg uses?"
( . "$ROOT/hooks/lib/verdict.sh" 2>/dev/null
  verdict_is_clean "$TOK"                     && say "    verdict_is_clean      : TRUE"  || say "    verdict_is_clean      : false"
  verdict_covers_head "$TOK" "$ROOT" "HEAD"   && say "    verdict_covers_head   : TRUE"  || say "    verdict_covers_head   : false" )

say ""
say "### Control: same state, falsifier ABSENT"
rm -f "$VERD"
out="$(run)"
say "    current guard      -> $(verdict_of "$out") / $(which_gate "$out")"
rm -rf "$HOME"
