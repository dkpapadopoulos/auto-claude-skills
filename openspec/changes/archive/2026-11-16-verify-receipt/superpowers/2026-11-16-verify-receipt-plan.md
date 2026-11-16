# Verification Receipt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One command renders the recorded verification verdict for the current commit as a short markdown receipt an agent pastes into a PR description, in any repo the plugin is installed on.

**Architecture:** `scripts/verify-receipt.sh` is a read-only renderer over the artifact `scripts/verify-and-record.sh` already writes. It sources `hooks/lib/verdict.sh` for token resolution and the measured/dirty/exact-commit predicates, and renders with one `jq` program. `verify-and-record.sh` names the command when a receipt can be rendered; `skills/project-verification/SKILL.md` says what to do with it.

**Tech Stack:** bash 3.2, jq, git. No network, no writes.

**Spec:** `openspec/changes/verify-receipt/` (`proposal.md`, `design.md`, `specs/project-verification/spec.md`), approved by the owner 2026-11-16 at commit `fff37908`.

**Files:**
- Create: `scripts/verify-receipt.sh`
- Create: `tests/test-verify-receipt.sh`
- Modify: `scripts/verify-and-record.sh` (closing output only, after line 575)
- Modify: `skills/project-verification/SKILL.md` (`## Output` section only)
- Modify: `openspec/changes/verify-receipt/specs/project-verification/spec.md`, `design.md` (Task 3 amendment)
- Modify: `CHANGELOG.md` (`## [Unreleased]` → `### Added`)
- NOT touched: `hooks/**`, `config/**`, `CLAUDE.md`, `.claude/rules/**`, `tests/test-injection-budget.sh`, `tests/test-claude-md-rule-split.sh`

## Global Constraints

- Bash 3.2 (`/bin/bash`): no associative arrays, no quoted operands in `$(( ))`, no `set -e`. Check with `/bin/bash -n`.
- Read a governed file with the Read tool before editing it.
- Every direct test or script invocation gets `< /dev/null`.
- Test artifacts come from the real `scripts/verify-and-record.sh` in explicit mode (`--name <n> --run <cmd>`) under `setup_test_env`'s isolated HOME. Never hand-write a verdict JSON, except by mutating a real one with `jq` for the two states the writer cannot produce on demand (non-measured `discovery_source`, foreign `writer`), and say so in a comment.
- Assertion loops run in the current shell (no piped `while`); verdicts via `_record_pass`/`_record_fail`/`assert_*`.
- Exit codes: `0` receipt printed; `1` no receipt; `3` cannot check. Stdout is empty unless the exit is `0`.
- The receipt never contains: `.command`, `.output_excerpt`, `.dirty_paths`, the token, `$HOME`.
- Marker, exact: `<!-- acs-verify-receipt v1 sha=<full sha> result=<pass|fail|could-not-verify|suspect> -->`.
- `skills/project-verification/SKILL.md` stays at or under 19,500 bytes (now 19,041); the addition is under 400 bytes.
- Commits: `<type>: <description>`, ending `Co-Authored-By: Claude <noreply@anthropic.com>`. Never amend. No push.
- The plugin runs on other people's repos: no text may assume this repo's paths, runner or sentinel.

## Review Focus

1. **A check name is user text that lands in a public PR body.** `--name` and `.verify.yml` names are validated only against `,`, newline and US, so a name can hold `-->`, a backtick, `@someone`, a pipe or a URL. Expected: a name is printed only if it matches `^[A-Za-z0-9._ -]{1,60}$` (the rule `verdict_unclean_remedy` uses); others are counted, not shown. (Task 2)
2. **A recorded field that is not what the writer writes.** `gate_gaming_status` or `ts` edited to free text. Expected: status printed only if `^[a-z-]{1,30}$`, else `unrecognised`; `ts` printed only if `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, else `unknown`. (Task 2)
3. **An artifact holding two JSON documents, or none.** Expected: exit 3, empty stdout (unslurped `jq` reads the last document). (Task 1)
4. **Run from a subdirectory of the repo, and from outside any repo.** Expected: same receipt from a subdirectory; exit 3 outside a repo. (Task 1)
5. **A failing sibling-session verdict at the same commit beside the caller's clean one.** Expected: the receipt is the failing one (`verdict_resolve_token` deny-bias applies only when the own token is NOT at exact HEAD; when own is at HEAD the own verdict is rendered — pin which, do not guess). (Task 2)

---

### Task 1: Receipt renderer — gates, exit codes, happy path

**Files:**
- Create: `scripts/verify-receipt.sh`
- Test: `tests/test-verify-receipt.sh`

**Interfaces:**
- Consumes from `hooks/lib/verdict.sh`: `verdict_artifact_path <token>`, `verdict_resolve_token <token> <root>`, `verdict_sha_is_head <token> <root>`, `verdict_is_measured <token>`, `verdict_measured_dirty <token>`. From `hooks/lib/session-token.sh`: `resolve_own_session_token`.
- Produces: `bash scripts/verify-receipt.sh` (no arguments; any argument → usage on stderr, exit 3). Stdout on exit 0, in this order:

```
<!-- acs-verify-receipt v1 sha=<40-hex> result=<result> -->
### Local verification: <PASS|FAIL|COULD NOT VERIFY|SUSPECT>

- Commit: `<40-hex>`
- Recorded: <ts> by `verify-and-record.sh` (<verify-yml|explicit>)
- Gate-gaming check: <status>

| Check | Outcome |
|---|---|
| <name> | passed |
| <name> | FAILED |
| <name> | could not run |

Produced on the author's machine from the recorded verdict for this commit. It is not CI and is not tamper-proof.
```

  Rows: failed first, then could-not-run, then passed. Zero checks → one row `| (no checks recorded) | - |`.

- [ ] **Step 1: Write the failing test file `tests/test-verify-receipt.sh`**

Header and fixtures follow `tests/test-verify-and-record.sh` lines 1-29 (`setup_test_env`, `export CLAUDE_PLUGIN_ROOT="${REPO_ROOT}"`, `unset SKILL_SESSION_TOKEN CLAUDE_CODE_SESSION_ID`, token file `session-rcpt`, `mkrepo`). Helpers:

```bash
RCPT="${REPO_ROOT}/scripts/verify-receipt.sh"
# record <repo> <args…> — run the REAL writer in explicit mode
record() { local r="$1"; shift; ( cd "$r" && /bin/bash "${VAR}" "$@" >/dev/null 2>&1 < /dev/null ); }
# render <dir> — sets OUT, ERR, RC
render() { OUT="$( cd "$1" && /bin/bash "${RCPT}" 2>"${TEST_TMPDIR}/err" < /dev/null )"; RC=$?; ERR="$(cat "${TEST_TMPDIR}/err")"; }
```

Cells (each `rm -f "${ARTIFACT}"` first):

| Cell | Setup | Assertions |
|---|---|---|
| R0 | — | file exists; `/bin/bash -n` passes |
| R1 clean | `record R --name unit --run true --name lint --run true` | RC=0; first line == `<!-- acs-verify-receipt v1 sha=$(git rev-parse HEAD) result=pass -->`; contains `\| unit \| passed \|` and `\| lint \| passed \|`; contains `Local verification: PASS`; contains `not CI`; contains `(explicit)` |
| R2 failing | `--name unit --run true --name e2e --run 'exit 3'` | RC=0; marker `result=fail`; `\| e2e \| FAILED \|`; `\| unit \| passed \|`; the `e2e` row's line number < the `unit` row's |
| R3 could-not-run | `--name types --run definitely-not-a-cmd-xyz` | RC=0; marker `result=could-not-verify`; `\| types \| could not run \|` |
| R4 HEAD moved | record clean, then `git commit --allow-empty -qm next` | RC=1; OUT empty; ERR contains the verified sha AND the new HEAD sha |
| R5 dirty tree | `echo y >> f.txt` (tracked, uncommitted), then record | precondition `jq -e '.worktree_dirty == true'`; RC=1; OUT empty; ERR contains `uncommitted` |
| R6 no verdict | fresh repo, nothing recorded | RC=1; OUT empty; ERR non-empty; `ls -A "${TEST_HOME}/.claude"` identical before and after |
| R7 not measured | record clean, then `jq '.discovery_source="claude-md-commands"'` over the real artifact (comment: writer cannot produce a ladder verdict) | RC=1; OUT empty; ERR contains `not measured` |
| R8 foreign writer | record clean, then `jq '.writer="by-hand"'` | RC=1; OUT empty |
| R9 two documents | record clean, then append `{"gate_gaming_status":"clean"}` to the artifact | RC=3; OUT empty |
| R10 not a repo | `render "${TEST_TMPDIR}"` (`GIT_CEILING_DIRECTORIES="${TEST_TMPDIR}"`) | RC=3; OUT empty |
| R11 no jq | PATH from `isolated_tool_path` without jq; first assert `command -v jq` fails under that PATH | RC=3; OUT empty |
| R12 subdirectory | record clean, `mkdir sub`, `render R/sub` (untracked empty dir does not dirty `-uno`) | RC=0; same marker as from the root |
| R13 argument | `/bin/bash "${RCPT}" --help` | RC=3; stdout empty |

End with `print_summary`.

- [ ] **Step 2: Run it, confirm it is red for the right reason**

Run: `bash tests/test-verify-receipt.sh < /dev/null`
Expected: R0 fails "script exists"; later cells fail on RC, none with `command not found` from the test's own helpers.

- [ ] **Step 3: Implement `scripts/verify-receipt.sh`**

Order of checks, each refusing before the next runs:

1. any argument → usage, exit 3
2. `git rev-parse --show-toplevel` fails → exit 3; `jq` missing → exit 3
3. `PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"`; source `hooks/lib/verdict.sh`, require `command -v verdict_resolve_token` → else exit 3
4. token: the same three-step resolution as `scripts/verify-and-record.sh` lines 196-202, copied, then `TOKEN="$(verdict_resolve_token "$TOKEN" "$ROOT")"`
5. artifact absent → exit 1 `no verdict recorded for this session or commit`
6. `jq -es 'length == 1 and (.[0] | type == "object")'` fails → exit 3
7. `.writer != "verify-and-record.sh"` or `! verdict_is_measured` → exit 1, message contains `not measured`
8. `! verdict_sha_is_head` → exit 1 naming `.sha` (printed only if it is 40 or 64 hex, else `unreadable`) and `HEAD`
9. `verdict_measured_dirty` → exit 1, message contains `uncommitted changes`
10. render with ONE `jq -r` program; print its output only if jq exits 0 and the output is non-empty, else exit 3

Result precedence: `fail` (any failed) > `could-not-verify` (any could-not-run) > `suspect` (status `suspect`) > `pass`. Every stderr line is prefixed `verify-receipt: `. Header comment states: reader only, exit status means "a receipt was rendered", not "the gate passed".

- [ ] **Step 4: Run the test, confirm green; syntax check**

Run: `bash tests/test-verify-receipt.sh < /dev/null; /bin/bash -n scripts/verify-receipt.sh`
Expected: `All tests passed`, exit 0.

- [ ] **Step 5: Commit**

`git add scripts/verify-receipt.sh tests/test-verify-receipt.sh` — `feat: render the recorded verification verdict as a commit-bound receipt`

---

### Task 2: Disclosure and hostile-field handling

**Files:**
- Modify: `scripts/verify-receipt.sh` (the jq program)
- Test: `tests/test-verify-receipt.sh`

**Interfaces:**
- Consumes: Task 1's renderer and test helpers.
- Produces: jq helper `def plain: test("^[A-Za-z0-9._ -]{1,60}$");`. A non-plain name is not printed; one extra row per outcome group: `| (<n> check(s) with a name that is not a plain label) | <outcome> |`.

- [ ] **Step 1: Add failing cells**

| Cell | Setup | Assertions |
|---|---|---|
| D1 secret in command | `--name deploy --run 'echo LEAKED-OUTPUT-7731; : --token=SECRET-TOKEN-4242'` | RC=0; precondition: artifact `.command` contains `SECRET-TOKEN-4242` and `.output_excerpt` contains `LEAKED-OUTPUT-7731`; OUT contains neither |
| D2 no local detail | same receipt | OUT does not contain `${TEST_HOME}`, `session-rcpt`, `.skill-project-verified` |
| D3 hostile name | `--name 'x --> @everyone'` `--run true` `--name ok --run true` (precondition: the writer accepted it) | RC=0; OUT does not contain `@everyone`; `grep -c -- '-->'` over OUT is exactly 1 (the marker); OUT contains `1 check(s) with a name that is not a plain label`; `\| ok \| passed \|` still present |
| D4 pipe in name | `--name 'a | b'` `--run 'exit 1'` | marker `result=fail`; OUT does not contain `a | b`; the not-plain row's outcome is `FAILED` |
| D5 edited status | real clean artifact, `jq '.gate_gaming_status="clean -->\n@x"'` (comment: writer cannot produce it) | RC=0; `Gate-gaming check: unrecognised`; no `@x` |
| D6 edited ts | `jq '.ts="yesterday <b>"'` | `Recorded: unknown`; no `<b>` |
| D7 suspect | real clean artifact, `jq '.gate_gaming_status="suspect"'` (comment: producing a real suspect needs a mainline base; `tests/test-gate-gaming-scope.sh` owns that path) | marker `result=suspect`; `Local verification: SUSPECT` |
| D8 sibling failure | own token `session-rcpt` records clean; then `SKILL_SESSION_TOKEN=session-other` records `--name unit --run 'exit 1'` at the same commit; render with no env token | pins observed behaviour: own exact-HEAD verdict is rendered (`result=pass`). Comment names `verdict_resolve_token` leg 1 and that the push gate has the same precedence |
| D9 sibling only | only `session-other` has a verdict at HEAD; own token has none | RC=0; receipt rendered from the sibling |

- [ ] **Step 2: Run, confirm D1-D2 pass or fail as the Task 1 program dictates and D3-D7 fail**

Run: `bash tests/test-verify-receipt.sh < /dev/null`
Expected: D3, D4, D5, D6 red. If D1/D2 are already green, mutate the jq program to print `.command`, confirm D1 goes red, restore.

- [ ] **Step 3: Implement the `plain` filter, the status and ts shape checks**

- [ ] **Step 4: Run, confirm green**

- [ ] **Step 5: Commit** — `feat: verification receipt shows plain check names only and no recorded free text`

---

### Task 3: The writer names the receipt command (and the spec says when)

**Files:**
- Modify: `scripts/verify-and-record.sh` (after line 576)
- Modify: `openspec/changes/verify-receipt/specs/project-verification/spec.md`, `design.md`
- Test: `tests/test-verify-receipt.sh`

**Interfaces:**
- Produces: one extra stdout line, last, exactly:
  `receipt for a PR description: bash '<escaped PLUGIN_ROOT>/scripts/verify-receipt.sh'`
  where `'` in the path is escaped as `'\''`. Printed iff `WORKTREE_DIRTY != true` AND `SHA_BEFORE == SHA_AFTER` AND the receipt script exists at that path. Otherwise nothing is added.

Why narrower than the committed spec: the spec says the command is printed after every measured verdict, but for a dirty-tree or straddled verdict the command refuses. A named remedy that cannot work is the defect `.claude/rules/remedy-reachability.md` exists for. The spec is amended in a NEW commit (no rewrite).

- [ ] **Step 1: Amend the spec and design**

In `spec.md` requirement 3, replace the first sentence with: "After `scripts/verify-and-record.sh` writes a measured verdict for which a receipt can be rendered (clean working tree, HEAD unchanged during the run), it MUST print the exact command that renders the receipt, as an absolute single-quoted path; otherwise it MUST NOT name the command." Add scenario "A dirty-tree verdict names no receipt command". In `design.md` decision 8 add one sentence saying the same and why. Run `openspec validate verify-receipt --strict`.

- [ ] **Step 2: Add failing cells**

| Cell | Setup | Assertions |
|---|---|---|
| W1 | clean explicit run, capture stdout | last line == `receipt for a PR description: bash '${REPO_ROOT}/scripts/verify-receipt.sh'` |
| W2 | take W1's last line, strip the prefix, `eval` it in the repo under `/bin/bash` | RC=0, output starts with the marker (the named command works as pasted) |
| W3 | dirty tree run | stdout does not contain `verify-receipt` |
| W4 | failing gate, clean tree | last line names the command (a failing receipt is still evidence) |
| W5 | copy `scripts/` + `hooks/lib/` + `skills/project-verification/scripts/` to `${TEST_TMPDIR}/pl ug'in/`, run the copy with `CLAUDE_PLUGIN_ROOT` set to it | pasting the named line under `/bin/bash` AND under `zsh` (skip the zsh half with a recorded pass-with-note if zsh is absent) renders a receipt; no file named by the path fragment after the quote is created |
| W6 | `.verify.yml` mode (`substrate: local`, one `echo ok` command, committed) | last line names the command; receipt says `(verify-yml)` |

- [ ] **Step 3: Check who reads the writer's stdout**

Run: `git grep -n 'tail -n *1\|tail -1' -- tests | grep -i 'verify-and-record\|VAR'` and `git grep -n 'verdict written' -- . ':!CHANGELOG.md'`. Any consumer that takes the LAST line of the writer's stdout must be updated in this task; list them in the commit body. Expected: none.

- [ ] **Step 4: Implement** (Read the file first). Escape with `_pr_q="$(printf '%s' "$PLUGIN_ROOT" | sed "s/'/'\\\\''/g")"`.

- [ ] **Step 5: Run `tests/test-verify-receipt.sh`, `tests/test-verify-and-record.sh`, `tests/test-verify-measured-verdict.sh`, `tests/test-verdict-dirty-tree.sh`, `tests/test-gate-gaming-scope.sh`, `tests/test-evaluator-surface.sh`, each `< /dev/null`**

Expected: all green.

- [ ] **Step 6: Commit** — two commits: `docs: receipt command is named only when a receipt can be rendered`, then `feat: verify-and-record names the receipt command after a renderable verdict`

---

### Task 4: Skill instruction and changelog

**Files:**
- Modify: `skills/project-verification/SKILL.md` (`## Output`)
- Modify: `CHANGELOG.md`
- Test: `tests/test-verify-receipt.sh`

- [ ] **Step 1: Add failing cells**

```bash
SK="${REPO_ROOT}/skills/project-verification/SKILL.md"
```
- S1: `SK` contains `'<PLUGIN_ROOT>/scripts/verify-receipt.sh'`
- S2: `SK` contains `verbatim` and `PR description` within the `## Output` section (extract with `sed -n '/^## Output/,$p'`)
- S3: `wc -c < SK` ≤ 19500

- [ ] **Step 2: Append to `## Output`, exactly** (≈370 bytes):

```
When the writer prints a receipt command, run it and paste its output verbatim into the PR description for that commit; after any later commit, verify again and replace it. If it refuses, say no receipt exists; never write one by hand:

`bash '<PLUGIN_ROOT>/scripts/verify-receipt.sh'`
```

- [ ] **Step 3: Run** `tests/test-verify-receipt.sh`, `tests/test-skill-reattach-budget.sh`, `tests/test-skill-plugin-root-reachable.sh`, `tests/test-skill-anatomy.sh`, `tests/test-skill-content-coverage.sh`, each `< /dev/null`. Expected: green.

- [ ] **Step 4: CHANGELOG** — one bullet at the top of `## [Unreleased]` → `### Added`: what it is, the refusal cases, outcomes-only disclosure, the limit (agent still pastes it; not a trust boundary), cell count measured from the final test run.

- [ ] **Step 5: Commit** — `feat: project-verification says to paste the receipt into the PR description`

---

### After the tasks (not tasks)

1. Review: fresh code reviewer over `origin/main..HEAD`; Codex as an adversarial tester of the renderer if the owner approves the send.
2. Recorded verify: `bash scripts/verify-and-record.sh` (full suite, ~13 min, run synchronously in the foreground of a background call without `nohup`); read the result from the verdict, then render this branch's own receipt with the new script.
3. Ask the owner before any push or PR.
