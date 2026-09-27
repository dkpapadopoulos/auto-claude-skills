#!/bin/bash
ROOT="$1"; H0="$2"; LIST="$3"
while IFS= read -r p; do
  [ -z "$p" ] && continue
  H="$(mktemp -d)"; mkdir -p "$H/.claude"
  # frontend-design ships in a separate plugin, undiscovered in this synthetic
  # HOME (see README.md), so the built registry always names it
  # available:false here regardless of the real install. Force it to
  # available:true in THIS PROMPT'S copy only, so the scan can see false
  # dispatches to it -- and assert the forcing actually took, so a jq
  # failure (or a future registry-shape change) reverts silently to the
  # exact blindness this scan exists to close, rather than reporting a
  # clean scan that never looked.
  jq '(.skills[] | select(.name == "frontend-design") | .available) = true' \
    "$H0/.claude/.skill-registry-cache.json" > "$H/.claude/.skill-registry-cache.json"
  fd_avail="$(jq -r '.skills[] | select(.name == "frontend-design") | .available' "$H/.claude/.skill-registry-cache.json")"
  if [ "$fd_avail" != "true" ]; then
    echo "FATAL: could not force frontend-design available:true in the scan registry -- refusing to report a scan that never looked" >&2
    rm -rf "$H"
    exit 1
  fi
  out="$(jq -nc --arg p "$p" --arg t "$H/.claude/a.jsonl" '{prompt:$p,transcript_path:$t}' \
    | HOME="$H" CLAUDE_PLUGIN_ROOT="$ROOT" /bin/bash "$ROOT/hooks/skill-activation-hook.sh" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // empty')"
  got=""
  for s in second-opinion panel design-debate synthesize prototype-lab frontend-design; do
    # frontend-design is a separate plugin, invoked as
    # Skill(frontend-design:frontend-design) rather than this plugin's
    # Skill(auto-claude-skills:<name>) form -- match per skill, not by a
    # single shared prefix.
    case "$s" in
      frontend-design) needle="frontend-design:frontend-design)" ;;
      *) needle="auto-claude-skills:${s})" ;;
    esac
    printf '%s' "$out" | grep -q "$needle" && got="${got}${s},"
  done
  [ -n "$got" ] && printf '%s\t%s\n' "${got%,}" "$p"
  rm -rf "$H"
done < "$LIST"
