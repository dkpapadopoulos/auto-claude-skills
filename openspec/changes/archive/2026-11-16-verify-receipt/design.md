# Design: verification receipt

## Intent

A reviewer of a PR written with this plugin, in any repo, can see what the
local gate returned for the commit under review, as generated text tied to that
commit, and can see plainly when no such evidence exists.

## Goals, non-goals, anti-goals

- Goal: one command renders the recorded verdict; it works with zero
  configuration wherever `verify-and-record.sh` works.
- Goal: the receipt never says more than was measured, and never appears for a
  commit that was not measured.
- Non-goal: enforcement. No deny, no gate, no CI check.
- Non-goal: proving correctness or resisting forgery. The verdict artifact is
  shell-writable; the receipt states its own provenance.
- Anti-goal: a receipt that reads as CI, leaks local detail (command lines,
  output, paths), or blocks a push when it cannot be produced.

## Approaches

| | A. PR-description block | B. Commit status | C. Both, staged |
|---|---|---|---|
| Host | any | GitHub only | — |
| Stale after a new commit | reader must compare shas | host shows no status | yes on GitHub |
| Outbound write by the plugin | none | one API call per push | opt-in |
| Relies on the agent | to paste | no | no, on GitHub |

**Chosen: C, staged (owner, 2026-11-16).** This change is step A: default,
host-agnostic, no network call. Step B is a separate change and opt-in, because
a plugin posting to GitHub by default on other people's repos must not be turned
on silently.

## Architecture

```
verify-and-record.sh ──writes──> ~/.claude/.skill-project-verified-<token>
        │ closing line names the receipt command
        ▼
verify-receipt.sh ──reads (hooks/lib/verdict.sh)──> markdown on stdout
        ▼
agent pastes it into the PR description (project-verification SKILL.md)
```

`verify-receipt.sh` is a reader. It sources `hooks/lib/verdict.sh` and resolves
the token the way `verify-and-record.sh` does. This session's own verdict is
used when it is for the exact commit, the push gate's first choice too.
Otherwise it uses a measured verdict another session recorded for the exact
commit, a failing one first. (Corrected after review, 2026-11-16: the first
text said a failing verdict always outranks a clean one, which is not what the
gate or this script does when the session has its own verdict at the commit;
and `verdict_resolve_token` is not used, because its bridge does not see a
could-not-verify or suspect sibling.)

## Decisions

1. **Exact commit only.** The receipt is rendered only when the verdict's `sha`
   equals `HEAD`. An ancestor verdict is refused with both shas named. The push
   gate accepts an ancestor for its own purposes; a receipt names one commit and
   must not describe another.
2. **Measured verdicts only.** `writer` is `verify-and-record.sh` and
   `discovery_source` is `verify-yml` or `explicit`. A hand-authored ladder
   verdict gets no receipt.
3. **A dirty-tree verdict is refused.** It measured files that are not in the
   commit.
4. **A failing verdict still gets a receipt**, headed FAIL, with the failing and
   could-not-run checks named. Exit status reports whether a receipt was
   rendered, not whether the gate passed, the same convention as
   `verify-and-record.sh`; the header line carries the result.
5. **Least data.** Check names and outcomes only. Never the command lines, the
   output excerpt, dirty paths, the token, or any path under the home directory.
   A user's command line can hold a credential, and a PR description is public
   in a public repo.
6. **A machine-readable first line**, an HTML comment
   `<!-- acs-verify-receipt v1 sha=<full sha> result=<pass|fail|could-not-verify|suspect> -->`,
   so the later commit-status step, or any reader, can find and compare it
   without parsing prose.
7. **Exit codes:** `0` receipt printed; `1` no receipt, reason on stderr;
   `3` cannot check (no `jq`, not a git repo, unreadable artifact). Stdout is
   empty unless the exit is `0`, so `$(verify-receipt.sh)` can never paste a
   refusal into a PR.
8. **Delivery is tool output plus one skill sentence, not a routing hint.** The
   routing display path is closed (compliance census, read 2026-11-15). The
   closing line of `verify-and-record.sh` is printed only after a measured
   verdict is written, and is rendered as an absolute, single-quoted command
   per `.claude/rules/remedy-reachability.md`.
   Amended at planning (2026-11-16): the line is printed only when a receipt
   can be rendered, that is, not for a dirty-tree verdict and not for a run
   that straddled a commit. Naming a command that will refuse is the defect
   that rule exists for.
9. **`skills/project-verification/SKILL.md` is at 19,041 of its 19,500-byte
   re-attach budget.** The added instruction stays under 400 bytes.

## Result vocabulary

| Receipt result | When |
|---|---|
| `pass` | no failed, no could-not-run, gate-gaming `clean`, at least one check passed |
| `fail` | any failed check |
| `could-not-verify` | no failed check, and: a check could not run, or the gate-gaming status is neither `clean` nor `suspect`, or no check is recorded |
| `suspect` | no failed or could-not-run check, gate-gaming status is `suspect` |

`pass` is never wider than `verdict_is_clean` in `hooks/lib/verdict.sh`. A
record whose `failed`, `could_not_verify` or `passed` is not an array, or whose
`worktree_dirty` is not a boolean, is not rendered (exit 3).

A gate-gaming status other than `clean` or `suspect` (for example
`unverified`) is printed as recorded when it is a lowercase word, and
`unrecognised` otherwise. It makes the result `could-not-verify`, never `pass`
(corrected after review: the first text let it stay a pass, against the table).

Amended at build (2026-11-16): a check name is printed only when it is a plain
label (letters, digits, dot, underscore, hyphen, space; at most 60 characters),
the rule `verdict_unclean_remedy` already applies. Any other name is counted
under its outcome. Names come from `--name` or `.verify.yml`, and the receipt
is pasted into a PR description, where `-->`, a mention or a pipe would act.

## Trade-offs

- The agent can still omit the receipt or write its own prose. Step B removes
  that dependence on GitHub. A guard that compares PR bodies with the artifact
  was considered and left out: it would add a parsing surface to
  `publish-guard.sh` for an advisory benefit.
- Refusing ancestor verdicts means a docs-only commit after verification leaves
  no receipt until the gate is run again. That is the honest state.

## Dissenting views

- Cross-model critique (Codex, 2026-11-16): prefers the receipt published
  automatically by the PR workflow so no agent step remains. Accepted as step B,
  opt-in.
- Earlier view in this session: not worth building, since the owner's own PRs
  already carry the line. Rejected by the owner: the plugin is for other
  people's repos.

## Safety classification

`private_data`: low (check names, a commit sha). `untrusted_input`: absent (the
script reads a local file it does not execute). `outbound_action`: absent in the
script; the agent's PR write is already covered by `publish-guard.sh`. Fewer
than two legs present.

## Verification strategy

Deterministic, test-first. `tests/test-verify-receipt.sh` builds a throwaway
git repo and produces every artifact with the real `verify-and-record.sh` in
explicit mode (never a hand-written JSON, per
`.claude/knowledge/classifier-fixtures-from-real-producer.md`), under an
isolated `HOME`, then asserts each scenario in the spec, plus: empty stdout on
every refusal, no leak of the command line or output excerpt, and bash 3.2
syntax.

## Left to the builder

Exact receipt wording; whether the closing line in `verify-and-record.sh` is
also printed for a failing measured verdict (default: yes, the receipt for a
failure is still evidence).
