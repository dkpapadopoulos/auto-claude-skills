#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-memory-leak-check.sh ==="

ENGINE="${PROJECT_ROOT}/scripts/memory-leak-check.sh"

WORK="$(mktemp -d /tmp/mlc-XXXXXX)"
MEM="${WORK}/memory"
REPO="${WORK}/repo"
mkdir -p "${MEM}" "${REPO}"

# A 20-word private run: long enough to exceed the 16-word threshold.
PRIVATE_RUN="the branch ledger record is overwritten in place rather than appended so a historical push cannot be replayed from it afterwards"
printf 'name: t\n---\n\n%s\n' "${PRIVATE_RUN}" > "${MEM}/feedback_ledger_overwrite.md"

# A run that exists in BOTH the corpus and tracked repo content.
PUBLIC_RUN="the composition state advances only when a chain member skill tool returns successfully which is why a trigger match alone is never evidence"
printf 'name: p\n---\n\n%s\n' "${PUBLIC_RUN}" > "${MEM}/project_public_overlap.md"

# Build a real git repo so `git ls-files` works.
( cd "${REPO}" && git init -q . \
  && printf '%s\n' "${PUBLIC_RUN}" > public.md \
  && git add public.md \
  && git -c user.email=t@t -c user.name=t commit -q -m init )

# Sets OUT and RC in the CURRENT shell. Never call this inside $( ) — a
# command substitution would set OUT in a subshell and the assertion would
# read a stale value.
_run() {  # _run <body-file>
    OUT="$( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            /bin/bash "${ENGINE}" "$1" 2>/dev/null )"
    RC=$?
}

# (a) Verbatim private run -> leak.
printf 'Some preamble.\n\n%s\n' "${PRIVATE_RUN}" > "${WORK}/leaky.md"
_run "${WORK}/leaky.md"
assert_equals "verbatim private run is flagged" "1" "${RC}"
assert_contains "names the source file" "feedback_ledger_overwrite.md" "${OUT:-<empty>}"

# (b) The deny output must NOT reproduce the matched text.
assert_not_contains "output does not echo matched text" "branch ledger record is overwritten" "${OUT:-}"

# (c) Same fact as a path:line citation -> clean.
printf 'Evidence: memory/feedback_ledger_overwrite.md:4 (feedback).\n' > "${WORK}/cited.md"
_run "${WORK}/cited.md"
assert_equals "path:line citation is clean" "0" "${RC}"

# (d) Public exemption: text in corpus AND tracked repo content -> clean.
printf '%s\n' "${PUBLIC_RUN}" > "${WORK}/public.md"
_run "${WORK}/public.md"
assert_equals "text already in tracked content is not a leak" "0" "${RC}"

# (e) File-boundary: tail of one memory file + head of the next must not match.
# NO frontmatter in these two fixtures on purpose: with a `name:` block, file
# B's own frontmatter words sit between the two runs, no adjacent cross-file
# sequence ever forms, and the case passes even against an engine with the
# per-file reset REMOVED. Verified by mutation.
printf 'alpha bravo charlie delta echo foxtrot golf hotel\n' > "${MEM}/aaa_first.md"
printf 'india juliett kilo lima mike november oscar papa\n'  > "${MEM}/bbb_second.md"
printf 'alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa\n' \
    > "${WORK}/spanning.md"
_run "${WORK}/spanning.md"
assert_equals "run spanning two memory files is not a match" "0" "${RC}"
rm -f "${MEM}/aaa_first.md" "${MEM}/bbb_second.md"

# (f) Short generic prose -> clean.
printf 'This fixes a bug in the hook.\n' > "${WORK}/short.md"
_run "${WORK}/short.md"
assert_equals "short generic prose is clean" "0" "${RC}"

# (g) Absent corpus -> clean (nothing to leak), announced on stderr.
OUT2="$( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${WORK}/nope" \
         /bin/bash "${ENGINE}" "${WORK}/leaky.md" 2>&1 )"
rc2=$?
assert_equals "absent corpus allows" "0" "${rc2}"
assert_contains "absent corpus is announced" "no memory corpus" "${OUT2:-<empty>}"

# (h) Missing argument -> usage error.
/bin/bash "${ENGINE}" >/dev/null 2>&1
assert_equals "no argument is a usage error" "2" "$?"

# (i) Unreadable body -> cannot check.
/bin/bash "${ENGINE}" "${WORK}/does-not-exist.md" >/dev/null 2>&1
assert_equals "unreadable body cannot be checked" "3" "$?"


# (j) I3: the public-content exemption must be repo-wide, not CWD-scoped.
# Put a public run in a tracked file inside a SUBDIRECTORY, then check the
# same body from a SIBLING subtree that never sees that file directly --
# `git ls-files -z` (unpatched) is scoped to CWD, so from `other/` the
# exemption corpus is empty and a legitimate publication false-blocks.
SUBTREE_RUN="the public exemption resolves every tracked file at head into one normalized line per file so a match cannot span files by accident"
printf 'name: s\n---\n\n%s\n' "${SUBTREE_RUN}" > "${MEM}/project_subtree_run.md"
mkdir -p "${REPO}/sub" "${REPO}/other"
( cd "${REPO}" && printf '%s\n' "${SUBTREE_RUN}" > sub/tracked.md \
  && git add sub/tracked.md \
  && git -c user.email=t@t -c user.name=t commit -q -m "add sub/tracked.md" )
printf '%s\n' "${SUBTREE_RUN}" > "${WORK}/subtree.md"

OUT3="$( cd "${REPO}/other" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
         /bin/bash "${ENGINE}" "${WORK}/subtree.md" 2>/dev/null )"
rc3=$?
assert_equals "public run tracked in a subdirectory is not a leak, even from a sibling subtree" "0" "${rc3}"

# --- S1: an unreadable corpus file must not report CLEAN ---------------------
# Both shingling pipelines end in `sort`, so the pipeline's exit status is
# sort's and awk's read failure is discarded. The shingle set comes out empty,
# which is indistinguishable from "no shingles", so the engine falls through
# `[ -s hits ] || exit 0` and returns 0 = CLEAN on a body that DOES leak.
# Contract: inability to check is exit 3, never a clean 0.
S1MEM="${WORK}/s1-memory"; mkdir -p "${S1MEM}"
S1RUN="a private run that must never reach the public tracker under any circumstances whatsoever and stays local"
printf 'name: s1\n---\n\n%s\n' "${S1RUN}" > "${S1MEM}/feedback_s1.md"
printf '%s\n' "${S1RUN}" > "${WORK}/s1-body.md"

# Control first: readable corpus => this body is a genuine leak (exit 1).
( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${S1MEM}" \
  /bin/bash "${ENGINE}" "${WORK}/s1-body.md" >/dev/null 2>&1 )
assert_equals "S1 control: readable corpus detects the leak" "1" "$?"

chmod 000 "${S1MEM}/feedback_s1.md"
( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${S1MEM}" \
  /bin/bash "${ENGINE}" "${WORK}/s1-body.md" >/dev/null 2>&1 )
s1rc=$?
chmod 644 "${S1MEM}/feedback_s1.md"
assert_equals "unreadable corpus file reports cannot-check (3), not clean (0)" "3" "${s1rc}"

# Body side: a --body-file naming a DIRECTORY passes `[ -r ]` but awk cannot
# read it, so the same silent-clean applies.
mkdir -p "${WORK}/s1-dir-body"
( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${S1MEM}" \
  /bin/bash "${ENGINE}" "${WORK}/s1-dir-body" >/dev/null 2>&1 )
assert_equals "a directory as body reports cannot-check (3), not clean (0)" "3" "$?"

# --- S3: a partially unbuildable public exemption must not become a LEAK -----
# `git ls-files -z | xargs -0 awk ... > repo || : > repo` TRUNCATES an already
# built exemption when any tracked path is unreadable. `[ -s repo ]` is then
# false, the exemption is skipped entirely, and every candidate is emitted as
# a leak — a false DENY asserting a leak that does not exist.
S3MEM="${WORK}/s3-memory"; mkdir -p "${S3MEM}"
S3RUN="this sentence is public because it is committed to the repository and therefore cannot possibly be a private leak"
printf 'name: s3\n---\n\n%s\n' "${S3RUN}" > "${S3MEM}/project_s3_public.md"
printf '%s\n' "${S3RUN}" > "${WORK}/s3-body.md"
( cd "${REPO}" && printf '%s\n' "${S3RUN}" > s3_public.md \
  && printf 'filler\n' > s3_extra.md && git add s3_public.md s3_extra.md \
  && git -c user.email=t@t -c user.name=t commit -q -m "add s3 public content" )

# Control: clean worktree => text is public => exempt => clean (0).
( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${S3MEM}" \
  /bin/bash "${ENGINE}" "${WORK}/s3-body.md" >/dev/null 2>&1 )
assert_equals "S3 control: public text is exempt when the exemption builds" "0" "$?"

# One tracked-but-deleted file (an ordinary mid-development state) makes awk
# fail, which truncated the whole exemption pre-fix.
rm -f "${REPO}/s3_extra.md"
( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${S3MEM}" \
  /bin/bash "${ENGINE}" "${WORK}/s3-body.md" >/dev/null 2>&1 )
s3rc=$?
( cd "${REPO}" && git checkout -q -- s3_extra.md 2>/dev/null )
# Acceptable outcomes: 0 (exemption still built, text public) or 3 (announced
# cannot-check). 1 means it asserted a leak that does not exist.
case "${s3rc}" in
    1) s3verdict="FALSE-LEAK (rc=1)" ;;
    0|3) s3verdict="not-a-leak" ;;
    *) s3verdict="unexpected rc=${s3rc}" ;;
esac
assert_equals "a deleted tracked file must not turn public text into a LEAK" "not-a-leak" "${s3verdict}"

rm -rf "${WORK}"
print_summary
exit $?
