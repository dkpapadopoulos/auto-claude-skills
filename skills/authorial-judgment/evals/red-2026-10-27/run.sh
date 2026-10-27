#!/bin/bash
# One fresh-context headless run. usage: bash run.sh <scenario> <control|skill> <rep>
# Scratch lives OUTSIDE the repo tree in $RED_WORK (default under $TMPDIR): the isolated
# HOME, cwd and outputs. A scratch dir under skills/ trips the on-disk lints even when
# gitignored (the CLI writes its own cache naming CLAUDE_PLUGIN_ROOT into HOME).
# Needs: $RED_WORK/home (isolated HOME, see README.md). SKILL_DIR selects which SKILL.md
# the skill arm carries (default: this skill).
set -u
R="$(cd "$(dirname "$0")" && pwd)"
RED_WORK="${RED_WORK:-${TMPDIR:-/tmp}/acs-red-2026-10-27}"
mkdir -p "$RED_WORK/out" "$RED_WORK/cwd"
SKILL_DIR="${SKILL_DIR:-$(cd "$R/../.." && pwd)}"
sc="$1"; arm="$2"; rep="$3"
d="$R/fixtures/$sc"; out="$RED_WORK/out/$sc-$arm-$rep"
[ -s "$out.txt" ] && exit 0
draft="$R/fixtures/drafts/$(cat "$d/draft")"
prompt="$out.prompt"   # per rep: concurrent reps must never share a file
{ cat "$d/ask-$arm.txt"; printf '\n---\n\n'; cat "$draft"; } > "$prompt"
sys="$out.sys"
{ printf 'The authorial-judgment skill has been invoked for this task and is in effect. Its content follows.\n\n'
  cat "$SKILL_DIR/SKILL.md"; printf '\n\n# references/red-flags.md\n\n'; cat "$SKILL_DIR/references/red-flags.md"; } > "$sys"
extra=()
[ "$arm" = skill ] && extra=(--append-system-prompt "$(cat "$sys")")
start=$(date +%s)
env -i HOME="$RED_WORK/home" PATH="$PATH" USER="$USER" LOGNAME="$USER" TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8 TERM=dumb \
  claude -p --model sonnet --tools "" --disable-slash-commands --strict-mcp-config \
  --setting-sources user --no-session-persistence --output-format text ${extra[@]+"${extra[@]}"} \
  < "$prompt" > "$out.tmp" 2> "$out.err"
rc=$?
end=$(date +%s)
printf 'rc=%s secs=%s\n' "$rc" "$((end-start))" > "$out.meta"
if [ "$rc" -eq 0 ] && [ -s "$out.tmp" ]; then mv "$out.tmp" "$out.txt"; else echo "FAILED $sc $arm $rep rc=$rc" >&2; fi
