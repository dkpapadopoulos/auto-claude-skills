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
# act on; `command_push_subject_is_partial` is
# an ANY-form and stay announce-only. Every NO-MATCH cell below is a control: it
# is a command the ALL-form must REFUSE to classify as a deletion, because
# classifying it would skip the content gates on a command that ships content.
D=command_push_is_all_deletions

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
# zsh `=( )` is process substitution too, and ZSH is the shell that actually
# executes these commands. Measured: `/bin/zsh -c 'cd =(touch /tmp/X; echo x)'`
# creates the file, so the inner command runs. Omitting it certified the shape
# this layer exists to stop — the substitution inside the deletion's own args.
_assert_pred "zsh =() process substitution"           1 $D 'git push --delete origin scratch && cd =(git push origin main)'
_assert_pred "zsh =() inside the deletion itself"     1 $D 'git push --delete origin =(git push origin main)'
# bash >=5.3 funsub; unreachable on bash 3.2 / zsh 5.9, pinned forward-looking.
_assert_pred "bash 5.3 funsub"                        1 $D 'git push --delete origin scratch && cd ${ git push origin main; }'
# ...and the narrow patterns must not swallow an ordinary ${VAR} expansion.
_assert_pred "ordinary brace expansion still certifies" 0 $D 'cd "${WT}" && git push --delete origin foo'

# A group closer GLUED to a FLAG. Refspec words were closer-stripped and flag
# words were not, so `--tags)` missed its literal arm and fell through to the
# generic `-*`, leaving broad=0. `--tags` pushes every tag "in addition to the
# refspecs explicitly listed", so these are content pushes that were certified
# as shipping nothing. The spaced form always refused, which is exactly why no
# group cell caught it — they all used a spaced `)` or a brace group with `;`.
_assert_pred "glued closer after --tags"              1 $D '(git push origin :x --tags)'
_assert_pred "glued closer, space after the paren"    1 $D '( git push origin :x --tags)'
_assert_pred "glued closer after --all"               1 $D '(git push --delete origin x --all)'
_assert_pred "glued closer after --mirror"            1 $D '(git push --delete origin x --mirror)'
# Control: the spaced twin must refuse too, so the cells above cannot pass
# merely because grouped commands stopped certifying altogether.
_assert_pred "spaced twin also refuses"               1 $D 'git push origin :x --tags'
# ...and a grouped GENUINE deletion must still certify, or the fix is just a
# blanket refusal of parenthesised commands.
_assert_pred "grouped genuine deletion still certifies" 0 $D '(git push --delete origin foo)'
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

# --- issue #238: shell redirection operands are not refspecs ----------------
# `git push … 2>&1 | tail -N` is what an agent naturally writes, and the
# redirection words were counted as refspecs. Two consequences, and the second
# is the one the issue does not name: the SUBJECT advisory fired on a push the
# gate had measured correctly (a confident over-report, which this repo already
# decided is worse than silence), AND `command_push_ref` returned EMPTY, so the
# gate silently fell back to measuring HEAD instead of the named ref — defeating
# #219's subject resolution for any redirected command.
#
# Pipes were already correct because they are segment boundaries; redirections
# are not, so they had to be recognised as words.
#
# THE MATCHER IS STRUCTURAL, NOT AN ENUMERATION. This predicate family has been
# bypassed five times by lists of shell syntax that turned out to be incomplete,
# so the test drives the SHAPE — an optional `&`/fd-digits run, then `<` or `>` —
# rather than a catalogue of spellings, and includes forms nobody wrote down.
_assert_pred "stderr-to-stdout is not a refspec"   1 command_push_subject_is_partial 'git push origin main 2>&1'
_assert_pred "glued stdout redirect"               1 command_push_subject_is_partial 'git push origin main >/tmp/o'
_assert_pred "spaced stdout redirect"              1 command_push_subject_is_partial 'git push origin main > /tmp/o'
_assert_pred "append redirect"                     1 command_push_subject_is_partial 'git push origin main >> /tmp/o'
_assert_pred "spaced fd redirect"                  1 command_push_subject_is_partial 'git push origin main 2> /tmp/o'
_assert_pred "both streams redirect"               1 command_push_subject_is_partial 'git push origin main &> /tmp/o'
_assert_pred "multi-digit fd redirect"             1 command_push_subject_is_partial 'git push origin main 10> /tmp/o'
_assert_pred "fd duplication to close"             1 command_push_subject_is_partial 'git push origin main 3>&-'
_assert_pred "stdin redirect"                      1 command_push_subject_is_partial 'git push origin main < /dev/null'
_assert_pred "herestring"                          1 command_push_subject_is_partial 'git push origin main <<< x'
_assert_pred "redirect plus pipe, the live shape"  1 command_push_subject_is_partial 'git push -u origin feat/x 2>&1 | tail -8'

# The ref must still RESOLVE through a redirection — this is the half that
# silently defeated #219, and an "is not partial" assertion alone would pass
# while the ref came back empty.
assert_equals "ref resolves through 2>&1"          "main" "$(command_push_ref 'git push origin main 2>&1')"
assert_equals "ref resolves through a redirect"    "main" "$(command_push_ref 'git push origin main > /tmp/o')"
assert_equals "ref resolves, live shape"           "feat/x" "$(command_push_ref 'git push -u origin feat/x 2>&1 | tail -8')"

# CONTROLS — stripping must not swallow a real refspec, and must not invent one.
_assert_pred "two refs with a redirect is partial" 0 command_push_subject_is_partial 'git push origin a b > /tmp/o'
_assert_pred "--all with a redirect is partial"    0 command_push_subject_is_partial 'git push --all origin 2>&1'
_assert_pred "deletion with a redirect is partial" 0 command_push_subject_is_partial 'git push --delete origin x 2>&1'
# A redirect TARGET is consumed with its bare operator, so the word after `>`
# is not counted — but a refspec BEFORE it still is.
assert_equals "target after bare > is not the ref" "main" "$(command_push_ref 'git push origin main > next')"
# A quoted word that merely begins with the operator character is NOT a
# redirection; it is a (pathological) ref name, and must not be stripped.
_assert_pred "quoted operator-lookalike is a ref"  1 command_push_subject_is_partial 'git push origin ">weird"'

# The ALL-form sees through redirections too — a redirect ships no content, so a
# redirected deletion is still deletion-only.
_assert_pred "redirected deletion certifies"       0 $D 'git push --delete origin foo > /tmp/o'
# ...but redirection stripping must not certify a command that ships content.
_assert_pred "redirected real push does not"       1 $D 'git push origin main > /tmp/o'

# `&` is a control operator EXCEPT immediately after `<` or `>`, where it is part
# of a redirection. This was pinned here as an accepted limitation — `2>&1` split
# into `… 2>` and `1`, the orphaned `1` was not on the inert whitelist, and the
# ALL-form correctly refused to vouch for a segment it could not account for.
#
# It stopped being acceptable once the redirection fix turned the same split into
# an UNDER-report: `git push origin main 3>&- next` lost `next` entirely, so a
# two-refspec push read as one. #198 calls that the strictly worse direction, and
# it was introduced by this change, so the splitter was narrowed instead. The
# narrowing is by construction: only an `&` whose previous character is `<` or
# `>` stops being a boundary, so `a && b`, `a & b` and a trailing `&` are
# untouched — pinned by the compound-command cells above and in
# tests/test-push-gate-failclosed.sh.
_assert_pred "&-redirect deletion now certifies"   0 $D 'git push --delete origin foo 2>&1'
_assert_pred "...and a redirected real push does not" 1 $D 'git push origin main 2>&1'
# The controls that must keep splitting.
_assert_pred "&& still separates commands"         1 $D 'git push --delete origin x && git push origin main'
_assert_pred "single & still separates"            1 $D 'git push --delete origin x & git push origin main'

# --- an ESCAPED operator must not merge two commands ------------------------
# The `&` narrowing above created a MERGE capability, and merging is what makes
# this scanner's documented "does not interpret backslash escapes" ceiling
# dangerous. Before the narrowing an escape could only cause OVER-splitting —
# the safe direction. After it, a word ending in `\>` made the `&` stop being a
# boundary, so the whole command collapsed into ONE segment whose first word is
# `echo`/`cd`/`true`, `_gc_segment_git_sub` never reported `push`, and no push
# segment was found at all.
#
#   echo a\>&git push origin main
#
# Real bash prints `a>`, backgrounds it, and RUNS THE PUSH. This is the
# DETECTION path, not the certification path: it does not need a deletion, does
# not consult the inert whitelist, and is not narrowed by _SUBJ_DELETION_ONLY —
# EVERY gate was skipped, including the fail-closed REVIEW/VERIFY gate. All three
# orthogonal layers miss it by construction (no substitution syntax; `\>` toggles
# no quote state so the parse is balanced; detection fails before the whitelist
# is reached).
#
# Measured across four different first words, so these pin the CLASS.
# ASSERTED END TO END, not through the ALL-form. The obvious unit cell here —
# "command_push_is_all_deletions refuses it" — is VACUOUS for this defect and was
# written that way first: when the bypass hides the push, the merged segment has
# no deletion either, so the ALL-form refuses for the WRONG reason and the cell
# passes against the bug. Mutation-verified: deleting the escaped-operator arm
# failed the e2e cells and the deletion cell, and left all four ALL-form cells
# green. Only a guard-level assertion separates "we measured the wrong thing"
# from "we did not gate at all".
#
# The chain seeded at the top of this file has REVIEW and VERIFY incomplete, so
# any DETECTED push must deny; a bypassed one produces no decision at all.
# Each cell asserts WHICH gate denied, not merely that the word "deny" appears.
# Asserting "deny" alone is correct only because a hidden push currently produces
# NO output at all — but the guard has a substring fallback for push detection
# when _GC_UNBALANCED is set, so if a future change ever marked these payloads
# untrusted, that fallback would find `git push` in the raw text, deny, and every
# one of these cells would go green while the scanner was bypassed again. Naming
# the fail-closed gate's own remedy text is what keeps them honest.
for _c in 'echo a\>&git push origin main' \
          'cd a\>&git push origin main' \
          'true a\>&git push origin main' \
          'echo a\<&git push origin main'; do
    out="$(_run "$_c")"
    assert_contains "escaped operator still reaches the gate: ${_c}" \
        "requesting-code-review has not run" "$out"
done

# NEW-2: the same root cause on the certification path. Here the ALL-form IS the
# right instrument, because the leading real deletion keeps the command
# detectable — so a pass genuinely means "refused to certify" rather than
# "never saw a push".
_assert_pred "escaped > cannot hide a push behind a deletion" 1 $D 'git push --delete origin foo; cd a\>&git push origin main'

# --- NEW-3: the HEREDOC seam ------------------------------------------------
#
#   cat <<EOF&git push origin main
#   EOF
#
# Real bash backgrounds `cat` with the heredoc attached and RUNS THE PUSH
# (measured with a file-creation oracle and a PATH-shimmed `git`, never with
# stdout text: bash quotes an offending command back in its syntax-error
# message, so grepping combined output for a marker reports commands that never
# ran — that mistake produced a phantom finding while this cell was written).
#
# WHY IT EXISTS, stated precisely because the obvious reason is wrong. Review of
# #242 proposed replacing the `'&')` arm's buffer-tail inspection with a flag
# raised when the scanner appends `<`/`>`. An escape-aware flag passes the four
# escaped-operator cells above AND this one, so this cell is NOT "the case a
# careful flag still gets wrong" — an earlier draft said that and it was
# measured false. What it pins is a DIFFERENT and likelier error: raising the
# flag on the `'<'` arm's HEREDOC branch. That variant leaves all five cells
# above green and merges this command, so before this cell the entire suite
# passed while detection was bypassed. It is the seam the rest of the suite
# does not cover, which is the whole of its claim to a place here.
#
# THE `EOF` TERMINATOR IS LOAD-BEARING. Without it `_pending` stays non-empty,
# so `_GC_UNBALANCED=1`, so the guard takes its fail-closed substring path,
# finds `git push` in the raw text and denies — and the cell passes while the
# scanner is bypassed. Measured both ways.
#
# That prose is not enough on its own, so the precondition is ASSERTED. The
# terminator is not the only route to an unbalanced parse: anything that stops
# `cat` classifying as a heredoc data sink (see the sink list in
# git-command.sh) also sends this payload down the substring path, and the cell
# would sit green forever. A cell whose non-vacuity rests on a comment pins
# nothing.
_assert_pred "NEW-3 payload parses balanced (else the cell below is vacuous)" 0 \
    command_parse_balanced 'cat <<EOF&git push origin main
EOF'
# Asserts the remedy text, not bare "deny", for the M9 reason: it pins WHICH
# gate denied, so a future change that widens a skip and shifts the deny to
# VERIFY or routing-governance is caught rather than absorbed. It does NOT
# distinguish the precise path from the substring fallback — both reach the
# same message — which is exactly why the balanced-parse assertion above has to
# carry that half.
out="$(_run 'cat <<EOF&git push origin main
EOF')"
assert_contains "heredoc operator cannot hide a trailing push" \
    "requesting-code-review has not run" "$out"

# THE DANGEROUS DIRECTION, pinned explicitly. A refspec-less `git push` ships the
# current branch, so it must NEVER certify as deletion-only — and redirection
# stripping is exactly the kind of change that could have made it, by removing
# the words that previously inflated the refspec count. It does not: the ALL-form
# requires an explicit deletion flag or an empty-source refspec, neither of which
# a redirect supplies. `git push` alone is already pinned above (line ~211); these
# add the REDIRECTED forms, which are the ones this change touches.
_assert_pred "redirected refspec-less push"        1 $D 'git push origin > /tmp/o'
_assert_pred "redirected refspec-less push, 2>&1"  1 $D 'git push origin 2>&1'
_assert_pred "redirected bare push"                1 $D 'git push > /tmp/o'

# Behaviour this change deliberately ALIGNED rather than left inconsistent.
# `git push --delete origin > main` used to count `>` and `main` as two refspecs
# and so refused; it now reads as a deletion with a redirect and certifies —
# matching `git push --delete origin`, which certified all along. Both ship no
# content (git rejects a --delete with no refspec), so the skip is harmless, and
# the redirected and unredirected forms giving different answers was the bug.
_assert_pred "redirect target is not a refspec (ALL-form)" 0 $D 'git push --delete origin > main'
_assert_pred "...matching the unredirected form"          0 $D 'git push --delete origin' 

# --- the `-` regression: a file named `-` is NOT an operator character -------
# Found in review, and it is the sixth-of-class pattern turned on my own fix: the
# operator-run class included `-` unconditionally, but `-` is only an operator
# when it follows `&` (the fd-close forms `>&-`, `3>&-`). Standing alone after
# `>` it is an ordinary FILENAME, so `>-` stripped to empty, classified as a bare
# operator, and swallowed the next word.
#
# `git push origin :scratch >- main` redirects to a file named `-` and pushes
# BOTH `:scratch` and `main`. Reading `main` as a redirect target left
# `refs=1 empty=1` — all refspecs are deletions — so the ALL-form CERTIFIED a
# command shipping real content and the guard skipped all four content legs.
# That is the one direction that is a security regression, and none of the three
# orthogonal layers catches it (one segment, no substitution, balanced parse).
_assert_pred "file named - does not certify"       1 $D 'git push origin :foo >- main'
_assert_pred "append to file named -"              1 $D 'git push origin :foo >>- main'
_assert_pred "read from file named -"              1 $D 'git push origin :foo <- main'
_assert_pred "fd redirect to file named -"         1 $D 'git push origin :foo 2>- main'
_assert_pred "double dash target"                  1 $D 'git push origin :foo >-- main'
# ...and the announce layer, where the same character converted #238's confident
# OVER-report into a confident UNDER-report on the same shape — strictly worse
# under the #198 rule this change cites.
_assert_pred "file named - is still multi-ref"     0 command_push_subject_is_partial 'git push origin main >- other'
# The fd-close form must keep working, and it must consume NOTHING (bash does not
# take a separate target for `3>&-`). A trailing-word cell cannot see the
# difference — `$# < 2` makes both classifications shift once — so the later word
# is what makes this observable.
# bash reads `git push origin main 3>&- next` as TWO refspecs — `3>&-` takes no
# separate target — so the correct answer is "partial". A TRAILING-word form
# cannot see the bare/glued difference at all (`$# < 2` makes both shift once),
# which is exactly why the first version of this cell passed against the defect
# it was written for.
_assert_pred "3>&- consumes no following word"     0 command_push_subject_is_partial 'git push origin main 3>&- next'

# CONTROL, in the form that actually pins it. The earlier version asserted only
# "not partial", which a SWALLOWED refspec also satisfies (refs=0) — so it passed
# even when the matcher ate the ref. Asserting the resolved ref is what fails.
assert_equals "quoted lookalike is a ref, by value" ">weird" "$(command_push_ref 'git push origin ">weird"')"

# bash >= 4.1 named-fd redirection. Announce-only and the safe direction (an
# unrecognised form over-counts and falls back to HEAD), but it is the #238
# symptom surviving for a real form.
_assert_pred "named-fd redirect is not a refspec"  1 command_push_subject_is_partial 'git push origin main {fd}>/tmp/o'
assert_equals "named-fd redirect resolves the ref" "main" "$(command_push_ref 'git push origin main {fd}>/tmp/o')" 
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
