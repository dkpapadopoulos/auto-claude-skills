#!/usr/bin/env bash
# test-checkpoint-validate.sh — integrity floor for openspec-ship checkpoint
# stamps (issue #129): every [checkpoint: <sha7>] in a retrospective tasks.md
# must be exactly 7 hex chars and a commit inside merge-base..HEAD.
# Spec: openspec/changes/checkpoint-stamping/specs/openspec-ship/spec.md
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-checkpoint-validate.sh ==="

VAL="${PROJECT_ROOT}/scripts/checkpoint-validate.sh"
assert_file_exists "validator script exists" "$VAL"

# Content gate: the consuming skill must reference the validator
# (skills/openspec-ship/ — also satisfies the content-coverage convention).
assert_contains "openspec-ship SKILL.md references the validator" \
    "checkpoint-validate.sh" "$(cat "${PROJECT_ROOT}/skills/openspec-ship/SKILL.md" 2>/dev/null)"

# --- scratch repo: mainline base + topic branch with two commits ---
R="$(mktemp -d /tmp/cpv-XXXXXX)"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
    && printf 'base\n' > f.txt && git add -A && git commit -q -m base \
    && git branch -m mainline \
    && git checkout -q -b topic \
    && printf 'one\n' >> f.txt && git commit -qam c1 \
    && printf 'two\n' >> f.txt && git commit -qam c2 ) 2>/dev/null
C1="$(git -C "$R" rev-parse --short=7 topic~1)"
C2="$(git -C "$R" rev-parse --short=7 topic)"
BASESHA="$(git -C "$R" rev-parse --short=7 mainline)"

_run() {  # _run <tasks-file-relpath> -> sets _out/_err/_rc
    _out="$(cd "$R" && /bin/bash "$VAL" "$1" mainline 2>/tmp/cpv-stderr)"; _rc=$?
    _err="$(cat /tmp/cpv-stderr 2>/dev/null)"
}

# 1: valid stamps + one bare task -> exit 0, correct summary
printf -- '- [x] 1.1 alpha [checkpoint: %s]\n- [x] 1.2 beta [checkpoint: %s]\n- [x] 1.3 bare task\n' "$C1" "$C2" > "$R/tasks.md"
_run tasks.md
assert_equals "valid stamps: exit 0" "0" "$_rc"
assert_contains "valid stamps: summary counts" "checkpoints: 2 stamped / 3 completed tasks" "$_out"

# 2: mainline base commit stamped -> out of range -> exit 1
printf -- '- [x] 1.1 alpha [checkpoint: %s]\n' "$BASESHA" > "$R/tasks.md"
_run tasks.md
assert_equals "base-commit stamp: exit 1" "1" "$_rc"
assert_contains "base-commit stamp: named on stderr" "$BASESHA" "$_err"

# 3: malformed stamps -> exit 1
printf -- '- [x] 1.1 short [checkpoint: abc12]\n' > "$R/tasks.md"
_run tasks.md
assert_equals "short stamp: exit 1" "1" "$_rc"
printf -- '- [x] 1.1 nonhex [checkpoint: zzzzzzz]\n' > "$R/tasks.md"
_run tasks.md
assert_equals "non-hex stamp: exit 1" "1" "$_rc"

# 4: uppercase valid SHA -> normalized -> exit 0
C1_UP="$(printf '%s' "$C1" | tr 'a-f' 'A-F')"
printf -- '- [x] 1.1 upper [checkpoint: %s]\n' "$C1_UP" > "$R/tasks.md"
_run tasks.md
assert_equals "uppercase stamp: exit 0 (case-normalized)" "0" "$_rc"

# 5: two stamps on one line, second bogus -> both parsed -> exit 1
printf -- '- [x] 1.1 dup [checkpoint: %s] [checkpoint: 1234567]\n' "$C1" > "$R/tasks.md"
_run tasks.md
assert_equals "duplicate stamps: second stamp validated too (exit 1)" "1" "$_rc"
assert_contains "duplicate stamps: summary counts both" "2 stamped" "$_out"

# 6: unrunnable -> exit 2
_run does-not-exist.md
assert_equals "missing file: exit 2" "2" "$_rc"
NOREPO="$(mktemp -d /tmp/cpv-norepo-XXXXXX)"
printf -- '- [x] 1.1 x\n' > "$NOREPO/tasks.md"
_o="$(cd "$NOREPO" && GIT_CEILING_DIRECTORIES=/private/tmp:/tmp /bin/bash "$VAL" tasks.md 2>/dev/null)"; _rc=$?
assert_equals "outside git repo: exit 2" "2" "$_rc"

# R1 (review fix): SKILL.md must invoke via plugin-root, not a bare repo path.
#
# The SPELLING this pinned was `${CLAUDE_PLUGIN_ROOT:-.}`, which #311 measured
# as the very failure the assertion's own comment forbids: `CLAUDE_PLUGIN_ROOT`
# is unset in the model's shell, so it fell through to `.` — the current working
# directory, i.e. a bare relative path that resolves wherever the model happens
# to be standing. The intent was right and the spelling was the defect.
#
# It now pins the plugin-root-qualified placeholder the session context tells
# the reader to substitute. Keep this keyed on "a plugin-root-qualified path",
# never on a bare `scripts/checkpoint-validate.sh`, which is what the intent
# has always excluded.
assert_contains "SKILL.md names the validator by a plugin-root-qualified path" \
    '<PLUGIN_ROOT>/scripts/checkpoint-validate.sh' \
    "$(cat "${PROJECT_ROOT}/skills/openspec-ship/SKILL.md" 2>/dev/null)"

# R2 (review fix): no-space stamp is validated, not silently ignored
printf -- '- [x] 1.1 nospace [checkpoint:%s]\n' "$BASESHA" > "$R/tasks.md"
_run tasks.md
assert_equals "no-space foreign stamp: still caught (exit 1)" "1" "$_rc"

# R3 (review fix): indented completed subtasks count in the denominator
printf -- '- [x] 1.1 top [checkpoint: %s]\n  - [x] 1.1.1 sub\n' "$C1" > "$R/tasks.md"
_run tasks.md
assert_contains "indented subtask counted" "1 stamped / 2 completed tasks" "$_out"

# R4 (codex review): unchecked tasks are not counted as completed
printf -- '- [x] 1.1 done [checkpoint: %s]\n- [ ] 1.2 pending\n' "$C1" > "$R/tasks.md"
_run tasks.md
assert_equals "unchecked task: exit 0" "0" "$_rc"
assert_contains "unchecked task: excluded from completed count" "1 stamped / 1 completed tasks" "$_out"

# 7: zero stamps -> exit 0, 0 stamped
printf -- '- [x] 1.1 bare\n- [x] 1.2 also bare\n' > "$R/tasks.md"
_run tasks.md
assert_equals "no stamps: exit 0" "0" "$_rc"
assert_contains "no stamps: summary" "checkpoints: 0 stamped / 2 completed tasks" "$_out"

rm -rf "$R" "$NOREPO" /tmp/cpv-stderr

print_summary
