#!/bin/bash
ROOT="$1"; H0="$2"; LIST="$3"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  H="$(mktemp -d)"; mkdir -p "$H/.claude"; cp "$H0/.claude/.skill-registry-cache.json" "$H/.claude/"
  out="$(jq -nc --arg p "$p" --arg t "$H/.claude/a.jsonl" '{prompt:$p,transcript_path:$t}' \
    | HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" /bin/bash "$ROOT/hooks/skill-activation-hook.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty')"
  got=""
  for s in second-opinion panel design-debate synthesize; do
    printf '%s' "$out" | grep -q "auto-claude-skills:${s})" && got="${got}${s},"
  done
  [ -n "$got" ] && printf '%s\t%s\n' "${got%,}" "$p"
  rm -rf "$H"
done < "$LIST"
