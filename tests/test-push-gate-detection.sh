#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-detection.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# REVIEW+VERIFY in chain, completed empty, no ledger, no verdict => a real push
# hits the fail-closed gate and DENIES. A non-write command must exit before that.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

_run() {
    jq -n --arg tp "$_TPATH" --arg c "$1" \
      '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# (a) Read-only command that merely mentions the phrase -> NO deny.
out="$(_run 'grep -nE "git push|deny" hooks/openspec-guard.sh')"
assert_not_contains "grep with phrase is not gated" '"deny"' "${out:-}"

# (b) echo mentioning the phrase -> NO deny.
out="$(_run 'echo "reminder: git push later"')"
assert_not_contains "echo with phrase is not gated" '"deny"' "${out:-}"

# (c) A real push with no evidence -> DENY (gate still fires).
out="$(_run 'git push origin HEAD')"
assert_contains "real push is gated" '"deny"' "${out:-<empty>}"

# (d) A real push via -C global flag -> DENY.
out="$(_run 'git -C /tmp/x push -u origin feature/y')"
assert_contains "push with -C is gated" '"deny"' "${out:-<empty>}"

# (e) Guard-level: a bare paren-wrapped push must reach the gate (real-world
#     impact of the trailing-closer fix — pre-fix this was silently allowed).
out="$(_run '(git push)')"
assert_contains "bare paren-wrapped push is gated" '"deny"' "${out:-<empty>}"

# Pre-filter: a large command with no "git" substring is not gated (and returns fast).
_big_nogit="echo $(printf 'x%.0s' $(seq 1 6000))"
out="$(_run "${_big_nogit}")"
assert_not_contains "large non-git command not gated" '"deny"' "${out:-}"

# Length cap: a >4096-char command that IS a real push still denies (substring fallback, fail-closed).
_big_push="git push origin HEAD # $(printf 'y%.0s' $(seq 1 4200))"
out="$(_run "${_big_push}")"
assert_contains "oversized real push still gated (fallback)" '"deny"' "${out:-<empty>}"

# --- Predicate units: gh-merge + compound mutate-then-push (audit F2) -------
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/git-command.sh"

_assert_pred() { # <desc> <expected 0|1> <fn> <cmd>
    local _rc=0
    "$3" "$4" >/dev/null 2>&1 || _rc=1
    assert_equals "$1" "$2" "${_rc}"
}

# command_invokes_gh_merge — MATCH (expect 0)
_assert_pred "gh pr merge (bare)"                 0 command_invokes_gh_merge 'gh pr merge'
_assert_pred "gh pr merge with number+auto"       0 command_invokes_gh_merge 'gh pr merge 123 --auto'
_assert_pred "gh -R repo pr merge"                0 command_invokes_gh_merge 'gh -R o/r pr merge 5'
_assert_pred "gh pr merge squash delete-branch"   0 command_invokes_gh_merge 'gh pr merge --squash --delete-branch'
_assert_pred "gh api REST pull merge"             0 command_invokes_gh_merge 'gh api -X PUT repos/o/r/pulls/5/merge'
_assert_pred "gh api graphql mergePullRequest"    0 command_invokes_gh_merge "gh api graphql -f query='mutation { mergePullRequest(input: {}) }'"
_assert_pred "gh merge after other segment"       0 command_invokes_gh_merge 'git fetch origin && gh pr merge 7'
# command_invokes_gh_merge — NO MATCH (expect 1)
_assert_pred "gh pr create mentioning merge"      1 command_invokes_gh_merge 'gh pr create --title "gh pr merge fix"'
_assert_pred "gh pr view"                         1 command_invokes_gh_merge 'gh pr view 5'
_assert_pred "echo phrase"                        1 command_invokes_gh_merge 'echo "gh pr merge"'
_assert_pred "git commit msg mentioning phrase"   1 command_invokes_gh_merge 'git commit -m "gh pr merge"'
_assert_pred "gh pr list piped to grep merge"     1 command_invokes_gh_merge 'gh pr list | grep merge'
_assert_pred "gh api unrelated endpoint"          1 command_invokes_gh_merge 'gh api repos/o/r/pulls/5/comments'

# command_git_mutate_before_push — MATCH (expect 0)
_assert_pred "commit && push"                     0 command_git_mutate_before_push 'git commit -m x && git push'
_assert_pred "add; commit; push"                  0 command_git_mutate_before_push 'git add -A; git commit -m x; git push origin HEAD'
_assert_pred "checkout+merge+push"                0 command_git_mutate_before_push 'git checkout main && git merge f && git push'
_assert_pred "rebase && push"                     0 command_git_mutate_before_push 'git rebase main && git push'
# command_git_mutate_before_push — NO MATCH (expect 1)
_assert_pred "plain push"                         1 command_git_mutate_before_push 'git push origin HEAD'
_assert_pred "pull && push (excluded set)"        1 command_git_mutate_before_push 'git pull && git push'
_assert_pred "push before commit"                 1 command_git_mutate_before_push 'git push && git commit -m x'
_assert_pred "quoted phrase only"                 1 command_git_mutate_before_push 'echo "git commit && git push"'

# Grouped forms: subshell/brace wrapping must not hide the invocation — a
# bare `(git push)` would otherwise evade the milestone gate entirely.
_assert_pred "paren-wrapped push detected"        0 command_invokes_git_write '(git push origin HEAD)'
_assert_pred "brace-group push detected"          0 command_invokes_git_write '{ git push origin HEAD; }'
_assert_pred "paren-wrapped gh merge detected"    0 command_invokes_gh_merge '(gh pr merge 5)'
_assert_pred "paren commit then push (compound)"  0 command_git_mutate_before_push '(git commit -m x) && git push'
_assert_pred "brace group commit;push (compound)" 0 command_git_mutate_before_push '{ git commit -m x; git push; }'
_assert_pred "quoted paren phrase still ignored"  1 command_invokes_git_write "echo '(git push)'"
# Trailing-closer forms: the closer glues onto the FINAL token when the
# subcommand (or its last arg) is last — review round 2 caught bare forms
# evading while the args-carrying test above stayed green.
_assert_pred "bare paren-wrapped push detected"   0 command_invokes_git_write '(git push)'
_assert_pred "cd-subdir paren push detected"      0 command_invokes_git_write '(cd sub && git push)'
_assert_pred "bare paren gh merge detected"       0 command_invokes_gh_merge '(gh pr merge)'
_assert_pred "fully-parenthesized compound"       0 command_git_mutate_before_push '(git commit -am x && git push)'
# gh api merge-status GET is a READ — must not be gated; PUT forms are writes.
_assert_pred "gh api GET merge-status not gated"  1 command_invokes_gh_merge 'gh api repos/o/r/pulls/5/merge'
_assert_pred "gh api --method PUT merge gated"    0 command_invokes_gh_merge 'gh api --method PUT repos/o/r/pulls/5/merge'

# Refactor guard: existing write-detection semantics must be unchanged.
_assert_pred "git push still detected"            0 command_invokes_git_write 'git push origin HEAD'
_assert_pred "git -C push still detected"         0 command_invokes_git_write 'git -C /tmp/x push'
_assert_pred "phrase-in-echo still not detected"  1 command_invokes_git_write 'echo "git push"'

# --- issue #155: newline inside a QUOTED argument is not a command boundary ---
# _gc_split_segments is quote-aware for ; | & but emits segments newline-delimited,
# and callers iterate with IFS=$'\n'. A newline inside quotes therefore survived the
# quote-aware scan and became a boundary anyway, so a multi-line quoted payload with
# a git-write-shaped LINE was classified as a real push. Measured in production: 5
# of 26 deny records were `node .../codex-companion.mjs "<multi-line prompt>"`
# invocations that push nothing (one of them deny:routing-governance, a push-only leg).
_MLQ='node /x/codex.mjs task "review this
git push origin main
and tell me why"'
_assert_pred "newline in quoted arg is not a boundary"   1 command_invokes_git_write "${_MLQ}"
_MLQ_SQ="node /x/codex.mjs task 'steps:
git push origin main
done'"
_assert_pred "newline in single-quoted arg either"       1 command_invokes_git_write "${_MLQ_SQ}"
# NOTE: a "quoted multi-line is not mutate-then-push" assertion was deliberately
# NOT added here. It passes on UNFIXED code for an unrelated reason — the final
# segment is `git push"` and _gc_segment_git_sub strips trailing )/} but not `"`,
# so the sub is `push"` != `push`. It would exert zero regression pressure while
# reading as coverage. Review caught it; the real guarantee is the e2e block below.

# ...but a REAL newline-separated compound (outside quotes) MUST still be detected —
# newline is a legitimate shell command separator; this is the other side of the fix.
_REAL='cd /tmp/x
git push origin HEAD'
_assert_pred "unquoted newline compound still detected"  0 command_invokes_git_write "${_REAL}"
_REAL_MUT='git commit -am x
git push'
_assert_pred "unquoted newline mutate-then-push caught"  0 command_git_mutate_before_push "${_REAL_MUT}"

# --- #155 follow-up: UNBALANCED-quote parses must never under-detect ----------
# Making newline a boundary inside the quote scanner made that scanner's quote
# state load-bearing for multi-line commands. Its model diverges from the
# shell's: it does not interpret backslash escapes, `#` comments, or heredoc
# bodies. An apostrophe in any of those leaves it falsely "inside a quote", the
# newline is consumed literally, and a following REAL push never becomes its own
# segment -> gate bypass. bash genuinely executes the push in every case below.
# The scanner must report the unbalanced parse so callers fail CLOSED.
# The lib predicates are DOCUMENTED fail-open and still miss these (they have no
# backslash/comment/heredoc model). The guarantee lives one layer up: the guard's
# _gc_precise rejects an unbalanced parse and drops to its fail-CLOSED substring
# path, so the push is still DENIED end-to-end. Assert the balance predicate at
# the lib layer and the deny at the guard layer.
_UB_COMMENT="# don't forget
git push origin HEAD"
_UB_ESC="echo it\\'s
git push origin HEAD"
_UB_HEREDOC="cat <<EOF
it's here
EOF
git push origin HEAD"

# Balance predicate: #155 payloads stay BALANCED (precise path preserved);
# bypass payloads are UNBALANCED (force the fail-closed fallback).
_assert_pred "quoted-newline payload parses balanced"    0 command_parse_balanced "${_MLQ}"
_assert_pred "awk-style single quotes parse balanced"    0 command_parse_balanced "awk '{print \$1}' f"
_assert_pred "nested quotes parse balanced"              0 command_parse_balanced "echo \"a 'b' c\""
_assert_pred "apostrophe comment parses unbalanced"      1 command_parse_balanced "${_UB_COMMENT}"
# remedy-aware-backbone: the heredoc body is now recognized as DATA (cat is a
# data sink), so the apostrophe in it no longer poisons quote state — the parse
# is BALANCED and the trailing push is detected PRECISELY instead of via the
# unbalanced fallback. The safety intent of the old expectation (the push after
# a heredoc must never be missed) is pinned by the paired predicate below and
# by the e2e "heredoc-apostrophe push still denied" assert.
_assert_pred "heredoc apostrophe parses balanced"        0 command_parse_balanced "${_UB_HEREDOC}"
_assert_pred "push after apostrophe heredoc detected"    0 command_invokes_git_write "${_UB_HEREDOC}"


# --- Predicate units: partial push subjects (issue #229) --------------------
# `command_push_is_all_deletions` is the ALL-form and the ONLY one a gate may
# act on; `command_push_is_multi_ref` and `command_push_subject_is_partial` are
# ANY-forms and stay announce-only. Every NO-MATCH cell below is a control: it
# is a command the ALL-form must REFUSE to classify as a deletion, because
# classifying it would skip the content gates on a command that ships content.
D=command_push_is_all_deletions
M=command_push_is_multi_ref

# ALL-form MATCH (expect 0) — commands that demonstrably ship no content.
_assert_pred "delete long flag"              0 $D 'git push --delete origin foo'
_assert_pred "delete short flag"             0 $D 'git push -d origin foo'
_assert_pred "empty-source refspec"          0 $D 'git push origin :foo'
_assert_pred "force marker on empty source"  0 $D 'git push origin +:foo'
_assert_pred "two empty-source refspecs"     0 $D 'git push origin :a :b'
_assert_pred "delete of two refs"            0 $D 'git push --delete origin a b'
_assert_pred "delete after a cd"             0 $D 'cd /tmp/x && git push --delete origin foo'
_assert_pred "delete in a brace group"       0 $D '{ git push --delete origin foo; }'
_assert_pred "delete with -C"                0 $D 'git -C /tmp/x push --delete origin foo'
_assert_pred "delete with -c config"         0 $D 'git -c k=v push --delete origin foo'
_assert_pred "delete with env prefix"        0 $D 'env FOO=1 git push --delete origin foo'
_assert_pred "delete inside a group"         0 $D '( git push --delete origin foo )'

# ALL-form NO MATCH (expect 1) — the controls. Each of these SHIPS CONTENT, so a
# fix that merely stopped denying would fail here.
_assert_pred "ordinary push is not a deletion"   1 $D 'git push origin main'
_assert_pred "bare push is not a deletion"       1 $D 'git push'
# THE control the ALL-form exists for: a deletion must never excuse a real push
# in the SAME command. This is why command_push_subject_is_partial stays
# announce-only — the ANY-form returns 0 for both of these.
_assert_pred "deletion then real push"           1 $D 'git push --delete origin x; git push origin main'
_assert_pred "real push then deletion"           1 $D 'git push origin main && git push --delete origin x'
_assert_pred "deletion mixed with a refspec"     1 $D 'git push origin :a main'
_assert_pred "deletion then --all"               1 $D 'git push --delete origin x; git push --all origin'
# --all/--mirror/--tags push refs that no refspec names, so "all refspecs are
# deletions" says nothing about what the segment ships.
_assert_pred "--all is not a deletion"           1 $D 'git push --all origin'
_assert_pred "--mirror is not a deletion"        1 $D 'git push --mirror origin'
_assert_pred "--tags is not a deletion"          1 $D 'git push --tags origin'
# These two are the cells that make the broad-flag disqualifier load-bearing.
# Without them the flag check is provably dead: mutation-tested by deleting the
# line, which left every other cell green — the three above pass on the refspec
# count alone (`--all origin` has no refspec, so it is already not-all-deletions).
# `--tags` alongside an empty-source refspec DOES ship content (every tag), and
# `--delete` would otherwise satisfy the deletion test on its own.
_assert_pred "--tags with a deletion refspec"    1 $D 'git push --tags origin :foo'
_assert_pred "--all combined with --delete"      1 $D 'git push --all --delete origin foo'
_assert_pred "--mirror combined with --delete"   1 $D 'git push --mirror --delete origin foo'
# A bare `:` names no ref on either half; guessing here would guess unsafely.
_assert_pred "bare colon is not a deletion"      1 $D 'git push origin :'
_assert_pred "src:dst refspec is not a deletion" 1 $D 'git push origin main:refs/heads/x'
_assert_pred "sha refspec is not a deletion"     1 $D 'git push origin deadbeef:refs/heads/x'
_assert_pred "no push at all"                    1 $D 'git status'
_assert_pred "push only inside a quoted string"  1 $D 'echo "git push --delete origin foo"'

# EVERY SEGMENT MUST BE ACCOUNTED FOR. "All recognized push segments are
# deletions" is a WEAKER claim than "this command ships no content", and these
# three were all CERTIFIED as deletion-only — while shipping real content —
# before `_gc_seg_is_inert` existed. The alias case is the sharpest: a git alias
# reports its own word from `_gc_segment_git_sub`, never `push`, so the segment
# is invisible to this predicate; it needs nothing new from git, and an alias in
# ~/.gitconfig works as well as the inline `-c` form. Reproduced end-to-end
# against the real guard (see tests/test-push-gate-subject.sh).
_assert_pred "alias-hidden push in the same command"  1 $D 'git push --delete origin x && git -c alias.p=push p origin main'
_assert_pred "script segment alongside a deletion"    1 $D 'git push --delete origin x && ./deploy.sh'
_assert_pred "bash -c segment alongside a deletion"   1 $D 'git push --delete origin x && bash -c "git push origin main"'
_assert_pred "another git subcommand alongside"       1 $D 'git branch -D x && git push --delete origin x'
# The cost is a forgone optimisation, never a new deny: an unaccountable segment
# falls back to measuring HEAD, i.e. today's behaviour. Even `echo` is refused —
# the whitelist is `cd` and pure punctuation only, because the parser cannot
# tell `echo` from `./deploy.sh` without a command table it would have to keep
# provably complete.
_assert_pred "even a harmless echo is not certified"  1 $D 'git push --delete origin foo && echo done'

# A command substitution RUNS wherever it appears — its output is only what
# happens afterwards. Each of these certified as deletion-only before the
# whole-command substitution guard existed, and each really pushes content
# (confirmed against real bash: the inner push completes and the ref reaches the
# remote before the outer command does anything with the captured output).
_assert_pred "substitution inside a cd argument"      1 $D 'git push --delete origin scratch && cd $(git push origin main)'
_assert_pred "backtick form of the same"              1 $D 'git push --delete origin scratch && cd `git push origin main`'
# THIS one is why the guard is whole-command rather than scoped to the `cd`
# whitelist entry: the substitution is an argument of the RECOGNISED deletion
# segment, so a cd-scoped fix — the obvious one once the shape above is known —
# would leave it open.
_assert_pred "substitution inside the deletion itself" 1 $D 'git push --delete origin $(git push origin main)'
_assert_pred "substitution glued to a refspec"        1 $D 'git push --delete origin x$(git push origin main)'
_assert_pred "process substitution"                   1 $D 'git push --delete origin x < <(git push origin main)'
# Bounded cost: an ordinary variable expansion is untouched, so the guard has
# not simply disabled certification for anything with a `$` in it.
_assert_pred "plain variable expansion still certifies" 0 $D 'cd "$WT" && git push --delete origin foo'
_assert_pred "variable refspec still certifies"         0 $D 'git push --delete origin "$BRANCH"'

# AN UNTRUSTWORTHY PARSE CANNOT CERTIFY. This scanner does not interpret
# backslash escapes, so outside an active quote a `\'` is a literal quote to real
# bash but toggles quote mode here — swallowing a genuine `;` and a real push
# into one segment whose first word is `cd`, which the whitelist then vouches
# for. It contains no `$(`, backtick or `<(`, so the substitution guard never
# sees it. `_GC_UNBALANCED`/`command_parse_balanced` already knew; the predicate
# just was not asking.
_assert_pred "escaped quote hides a trailing push"  1 $D "git push --delete origin scratch; cd \\'; git push origin main"
# ...and the bounded cost, stated: an unbalanced command with nothing hidden in
# it merely loses the skip and falls back to measuring HEAD.
_assert_pred "an unbalanced but harmless command also falls back" 1 $D "git push --delete origin it\\'s"
# The two are distinguishable only by the predicate's REASON, so pin that the
# balanced twin of the harmless case does still certify — otherwise the cell
# above passes equally well if certification broke outright.
_assert_pred "the balanced twin still certifies"    0 $D 'git push --delete origin its'

# Separators other than `&&`, and command wrappers, must all reach the segment
# whitelist rather than sneaking a second push past it. Probed as a class after
# two reported bypasses each turned out to be an instance of a wider one.
_assert_pred "pipe-both separator"           1 $D 'git push --delete origin x |& git push origin main'
_assert_pred "background separator"          1 $D 'git push --delete origin x & git push origin main'
_assert_pred "or separator"                  1 $D 'git push --delete origin x || git push origin main'
_assert_pred "newline separator"             1 $D 'git push --delete origin x
git push origin main'
_assert_pred "subshell group after deletion" 1 $D 'git push --delete origin x; ( git push origin main )'
_assert_pred "xargs wrapper"                 1 $D 'git push --delete origin x && xargs git push origin main'
_assert_pred "sudo wrapper"                  1 $D 'git push --delete origin x && sudo git push origin main'
_assert_pred "time wrapper"                  1 $D 'git push --delete origin x && time git push origin main'
_assert_pred "exec wrapper"                  1 $D 'git push --delete origin x && exec git push origin main'
_assert_pred "command wrapper"               1 $D 'git push --delete origin x && command git push origin main'
_assert_pred "heredoc into a shell"          1 $D 'git push --delete origin x && bash <<EOF
git push origin main
EOF'
# CERTIFIED, and correctly so: the quotes make this ONE refspec argument, so git
# is asked to delete a ref literally named `x && git push origin main` and errors
# — nothing is pushed. Pinned because it LOOKS like the bypass shape and a future
# reader may otherwise "fix" it into a false deny.
_assert_pred "quoted boundary is one refspec, not two commands" 0 $D 'git push --delete origin "x && git push origin main"'
# An absolute git path is a real git invocation; a differently-named binary is not.
_assert_pred "absolute git path certifies"   0 $D '/usr/local/bin/git push --delete origin x'
_assert_pred "a lookalike binary does not"   1 $D 'mygit push --delete origin x'

# Adversarial shapes. The command text is MODEL-AUTHORED, so a false POSITIVE
# here skips routing-governance on a command that ships content. Every cell
# below was measured against the parser, not reasoned about.
# Option-value forms: an option that eats the following word must not turn a
# content-bearing push into a deletion, and must not be mistaken for one.
_assert_pred "value-taking option before a deletion" 0 $D 'git push --repo x origin :a'
_assert_pred "option value eats a ref-shaped word"   0 $D 'git push --receive-pack main origin :a'
_assert_pred "a live refspec survives the option"    1 $D 'git push -o v origin :a main'
_assert_pred "equals-form option with a deletion"    0 $D 'git push --push-option=v origin :a'
_assert_pred "equals-form option with a real push"   1 $D 'git push --exec=x origin main'
# `--delete` as the VALUE of a value-taking option is not a deletion flag.
_assert_pred "--delete consumed as an option value"  1 $D 'git push --repo --delete origin x'
# End-of-options.
_assert_pred "-- before a deletion"                  0 $D 'git push -- origin :a'
_assert_pred "-- between remote and deletion"        0 $D 'git push origin -- :a'
_assert_pred "-- with a live refspec too"            1 $D 'git push -- origin :a main'
# The gate sees LITERAL text: anything shell-expanded is unknown, and unknown
# must never resolve to "deletion".
_assert_pred "command substitution alongside"        1 $D 'git push origin :a $(echo main)'
_assert_pred "variable refspec alongside"            1 $D 'git push origin :a "$BRANCH"'
_assert_pred "wholly variable refspec"               1 $D 'git push origin "$SPEC"'
_assert_pred "escaped colon is not an empty source"  1 $D 'git push origin \:a'
_assert_pred "quoted refspec with a space"           1 $D 'git push origin ":a main"'
# DOCUMENTED CEILING, asserted so it is a known state rather than a surprise:
# `--delete` supplied as the value of an option this parser does not model would
# be read as the deletion flag. Every value-taking `git push` option that exists
# today is modelled, so this needs a git option that does not exist; it is the
# same class as the `bash -c` indirection ceiling.
_assert_pred "ceiling: --delete after an unmodelled option" 0 $D 'git push --unknownopt --delete origin main'

# ANY-form multi-ref (announce-only).
_assert_pred "--all is multi-ref"            0 $M 'git push --all origin'
_assert_pred "--mirror is multi-ref"         0 $M 'git push --mirror origin'
_assert_pred "--tags is multi-ref"           0 $M 'git push --tags origin'
_assert_pred "two refspecs is multi-ref"     0 $M 'git push origin a b'
_assert_pred "mixed delete+ref is multi-ref" 0 $M 'git push origin :a main'
_assert_pred "single refspec is not multi"   1 $M 'git push origin main'
_assert_pred "bare push is not multi"        1 $M 'git push'
_assert_pred "single deletion is not multi"  1 $M 'git push --delete origin foo'

# A word made only of group closers is punctuation, not a refspec. Before this
# was fixed, a parenthesised push written with spaces and no trailing semicolon
# counted the closer as a third positional: the ref stopped resolving (so the
# gate fell back to the checkout HEAD) and a single-ref push was announced as
# carrying more than one.
assert_equals "grouped push resolves its ref"      "main" "$(command_push_ref '( git push origin main )')"
assert_equals "grouped brace push resolves"        "main" "$(command_push_ref '{ git push origin main; }')"
assert_equals "ungrouped push still resolves"      "main" "$(command_push_ref 'git push origin main')"
_assert_pred "grouped single push is not partial"  1 command_push_subject_is_partial '( git push origin main )'
_assert_pred "grouped multi push is still partial" 0 command_push_subject_is_partial '( git push origin a b )'
# Routing the ANY-form through the shared shape changed three answers, all
# deliberately, and each is pinned so it stays a decision rather than drift.
# (1) A force-marked deletion was MISSED before: the old private loop matched
#     `:*` literally, which `+:x` does not start with, so a real deletion was
#     never announced and the gate measured HEAD without saying so.
_assert_pred "force-marked deletion is partial"    0 command_push_subject_is_partial 'git push origin +:x'
# (2)+(3) are the bare-closer cells above.
# A bare `:` must stay announce-worthy while NOT being a deletion — the two
# callers disagree about it on purpose, which is why the shape carries `odd`.
_assert_pred "bare colon is still partial"         0 command_push_subject_is_partial 'git push origin :'
_assert_pred "bare colon is still not a deletion"  1 $D 'git push origin :'
# END-TO-END: unbalanced-quote payloads carrying a real push must still DENY.
out="$(_run "${_UB_COMMENT}")"
assert_contains "apostrophe-comment push still denied" '"deny"' "${out:-<empty>}"
out="$(_run "${_UB_ESC}")"
assert_contains "escaped-quote push still denied"      '"deny"' "${out:-<empty>}"
out="$(_run "${_UB_HEREDOC}")"
assert_contains "heredoc-apostrophe push still denied" '"deny"' "${out:-<empty>}"
# ...and the #155 false-block payload must still be ALLOWED (fix not undone).
out="$(_run "${_MLQ}")"
assert_not_contains "quoted-newline payload still allowed" '"deny"' "${out:-}"

export HOME="$_OLDHOME"
print_summary
exit $?
