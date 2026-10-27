# .claude/rules/outbound-guards.md history

Narrative moved out of the path-scoped rule `.claude/rules/outbound-guards.md` so that
the rule keeps only what a model must follow when it changes what may leave the machine.
The rule loads when the publish guard, the egress-consent hooks and dispatcher, the
reviewer-evidence hook, their tests, or the `improvement-miner`, `panel` and
`second-opinion` skills are touched. Nothing loads this file; it exists so the history
is not lost. Each section reproduces the original unit **verbatim** (as of commit
`dab9efd7`), names the test, if any, that now guards what was moved, and says where its
surviving instruction lives. Every section was moved in the commit
`docs: outbound-guards rule keeps its instructions and moves test-guarded history to docs/history`
(the commit that created this file: `git log --diff-filter=A -- docs/history/rules-outbound-guards.md`).
Review corrections followed in
`docs: outbound-guards rule restores the size-gate tail and the measured-key note`: two
clauses first listed here as moved were put back in the rule, and the notes below say so.

## Preamble: "Path-scoped rule, split out of the repo-root `CLAUDE.md` ..."

Moved in: the commit named above. Guard: none. Its last sentence, "Every bullet is
verbatim", stopped being true when stage 1 of the prose cleanup and later changes (#379)
edited the bullets. Still in force: the preamble's first sentence, followed by a pointer
to this file.

Original text:

> Path-scoped rule, split out of the repo-root `CLAUDE.md` Gotchas section so it
> loads only when you touch the files it governs. Every bullet is verbatim.

## Bullet: "Publication is a separate trust boundary from intake — for the `gh` verbs this gate covers."

Moved in: the commit named above. Most of this bullet is instruction and stays. Moved,
with the test that guards each:

- "Before this was added the shape was a **complete silent bypass**, and the tell was
  that `--body-file <(…)` announced while `--body "$(…)"` said nothing." Guard:
  `tests/test-publish-guard.sh` lines 274-281 (`$(…)`, `$VAR` and backtick bodies each
  announce "could not check"), lines 285-286 (a literal body stays silent), lines
  290-291 (the announcement fires even when a `--body-file` also resolved).
- "(one `rm` of a tracked file is enough)". Guard: `tests/test-memory-leak-check.sh`
  lines 152-171 (control: the exemption builds and public text is exempt; then one
  tracked file is deleted and the result must be 0 or 3, never a leak).
- "(this is why all four defects shipped green)". Guard: the announce cells that now
  exist for each silent path: `tests/test-memory-leak-check.sh` lines 115-137 (an
  unreadable corpus file or a directory body exits 3, with a readable-corpus control),
  lines 144-171 (above); `tests/test-publish-guard.sh` lines 244-265 (the corpus probe's
  own `mktemp` failing announces), lines 293-301 (an unresolvable plugin root
  announces), lines 274-291 (above).
- "so the private words are simply not there at scan time" was folded into "reach the
  hook as the *unexpanded* string"; same guard as the first item.
- Reworded, nothing removed: "Shingles are built PER FILE" and "The public exemption is
  load-bearing" became imperatives ("Build shingles", "Keep the public exemption"), "Before
  ... The expansion check sits deliberately OUTSIDE" became "Keep the expansion check
  OUTSIDE", and the mid-bullet Regression line moved to the end of the bullet.

Other guards for what the rule still states: `tests/test-publish-guard.sh` lines 28-43
(issue create, comment, edit and inline `--body` deny; the deny names the source file and
does not echo the text), lines 54-55 and 69-70 (merges untouched), lines 60-103 (`gh
api` forms, `--input` and `name=@path`, in either flag order), lines 112-121 (a
dangling `--input` and an absent corpus announce), lines 209-214 (no jq announces);
`tests/test-memory-leak-check.sh` lines 52-55 and 91-107 (public exemption, repo-wide),
lines 57-67 (no match spans two memory files). `tests/test-push-gate-canary.sh` lines
100-110 and `tests/test-plugin-drift-canary.sh` lines 65-75 pin the canary and drift
manifest coverage. Kept in the rule as instructions, reasons or stated limits. Of
these, no test pins the 16-word value or its measurement (`scripts/memory-leak-check.sh`
line 16 sets it; the tests only use runs longer than 16 words), the filename residual
gap and its count, the command-injection note and #174, `publish-guard.sh`'s exclusion
from `_GATE_ENFORCE_LIBS` (`tests/test-publish-guard-hardening.sh` lines 163-171 pin
only the engine's), or the rule that tests assert the announcement.

Still in force: the bullet in the rule, reworded only where a removed clause left a
sentence to rejoin.

Original text:

> - **Publication is a separate trust boundary from intake — for the `gh` verbs this gate covers.** `improvement-miner` may READ the whole local memory corpus but may not PUBLISH it: `hooks/publish-guard.sh` (PreToolUse `Bash` matcher ONLY) denies `gh issue|pr create|comment|edit` and `gh api` POST/PATCH-or-field-bearing calls against an issue/PR endpoint (`*/pulls/*/merge` excluded — no body, already the push gate's territory) whose body reproduces a 16+-word run present in `~/.claude/projects/<slug>/memory/` and absent from the repo's tracked content, via `scripts/memory-leak-check.sh`. The body is resolved from `--body-file`/`-F` (issue/pr) or `--input`/`-f|-F|--field|--raw-field name=@<path>` (`gh api`) when it names a FILE, else from the whole command string (covers any inline value without parsing it). This is NOT a general outbound guarantee: `gh pr review`, `gh release`, `gh gist`, `gh api graphql` mutations, and every non-Bash channel (MCP writes to Jira/Confluence etc.) are uncovered. Detection is fail-closed; inability to check (no corpus, no jq, unreadable body) is fail-open AND announced. Threshold 16 is read off a measured 16–25 plateau (0 false positives across 19 held-out non-miner issues; N=8 would deny 8 of 19). Shingles are built PER FILE — a shared word buffer fabricates matches spanning two files. The public exemption is load-bearing, not an optimization: without it, any issue restating a CLAUDE.md gotcha is denied. Residual gap, accepted: the citation publishes the memory FILENAME, and ~1 slug in 164 names a client — reviewed at the miner's human gate, because proper-noun matching is the fitted-heuristic failure mode the design rejects. `SKILL.md`'s `--body-file` rule is a COMMAND-INJECTION control and is not confidentiality — that misreading is what kept #174 open. PAIRED: `publish-guard.sh` is parse-checked in the session-start canary and in the drift manifest, but must NOT join `_GATE_ENFORCE_LIBS` (source-probed). Regression: `tests/test-memory-leak-check.sh`, `tests/test-publish-guard.sh`. **The gate scans LITERAL command text only — a shell-expanded body is unscannable by construction, not a parser bug to fix.** `--body "$(cat f)"` / `"$VAR"` / backticks reach the hook as the *unexpanded* string, so the private words are simply not there at scan time; the guard therefore ANNOUNCES `body may be shell-expanded` rather than pretending to have checked (it cannot deny on it — the expansion is evidence we could not look, not evidence of a leak). Before this was added the shape was a **complete silent bypass**, and the tell was that `--body-file <(…)` announced while `--body "$(…)"` said nothing. The expansion check sits deliberately OUTSIDE the "zero body-files resolved" branch: a command can resolve one `--body-file` AND carry a second expanded `--body`. **Both silent-failure classes here are pipeline-status bugs and will recur wherever `awk | sort` is used:** a pipeline ending in `sort` reports SORT's status, so a leading `awk`'s read failure vanishes and an empty shingle set reads as "clean" — use `PIPESTATUS[0]` and exit 3 (cannot-check), never let a read failure surface as 0. Symmetrically, NEVER write `cmd > "$OUT" || : > "$OUT"` for the public exemption: truncating a partial exemption turns every candidate into a false LEAK (one `rm` of a tracked file is enough), so append to a pre-truncated file and treat an incomplete build as exit 3. Any top-level assignment whose value comes from a command substitution (`X="${VAR:-$(cd … && pwd)}"`) trips the blanket `trap 'exit 0' ERR` *at that line*, i.e. above every announce path below it — split it into an `if` with an explicit `|| X=""`. PAIRED: tests must assert the ANNOUNCEMENT, not `assert_equals "" "$out"` — an empty-output assertion passes when the hook never ran at all and cannot tell "checked and clean" from "never checked" (this is why all four defects shipped green).

## Bullet: "`hooks/reviewer-evidence-hook.sh` observes a reviewer subagent's DISPATCH, not its return ..."

Moved in: the commit named above. Moved, with the test that guards each:

- The heading's second half, "and five easy mistakes there each cost a silent no-op or
  a false credit rather than an error". Guard: the cells below, one per mistake.
- "in three transcripts" (the 23-call measurement itself stays in the rule; no test
  replays a real spawn acknowledgement).
- "prefix matching credited 3/9 genuine reviews at 0/7 false positives". Guard:
  `tests/test-reviewer-evidence-hook.sh` lines 66-83 (the comment records the 3-of-9
  miss; mid-string "review:" and "re-review" must credit), lines 85-113 (the noun
  "reviewer" and "code-reviewer" in task names must not). The word-boundary versus
  substring figures stay in the rule as the reason not to widen it.
- "**A worktree split is therefore not by itself a cause of a missed read**, and this
  bullet previously said it was." ("— measured 2026-09-07 —" was first moved too and
  is back in the rule, because no test pins the same-branch claim.) Guard: none for the
  narrative about this bullet's earlier wording; the conclusion stays as the rule's
  instruction not to cite a different worktree. `tests/test-branch-ledger.sh` lines
  30-35 (same branch name, different repo: not shared) and lines 41-43 (detached HEAD is
  a different key) pin the key's parts; no test asserts that two worktrees on one branch
  share a key.
- "The real divergences are", "so the practical warning stands but its cause is the
  BRANCH, not the directory". Folded into the rule's two-cause sentence ("A missed read
  comes from (a) ... or (b) ..."), which keeps both causes and the instruction.
- The inline "(regression: ...)" citations after the matcher, typed-index, predicate,
  D4 and `dispatch_evidence` sentences, collapsed into one Regression line. Guards:
  `tests/test-reviewer-evidence-hook.sh` lines 39-47 (`Agent` and legacy `Task` both
  record), lines 131-150 (array, string and key-less `tool_response` still credit;
  `is_error: true` does not), lines 233-251 (`hooks.json` matcher is `^(Task|Agent)$`,
  and no `^Task$`-only matcher remains); `tests/test-review-verdict.sh` lines 626-642
  (observed, asserted and absent dispatch; a miss falls through to `asserted`), lines
  727-760 (an unresolvable PR plus the flag is not `imported`), lines 765-818
  (`imported` outranks `observed`).

Still in force: the bullet in the rule. The reviewer-arm sentence added by #379 is
unchanged.

Original text:

> - **`hooks/reviewer-evidence-hook.sh` observes a reviewer subagent's DISPATCH, not its return, and five easy mistakes there each cost a silent no-op or a false credit rather than an error.** `PostToolUse` for `Agent`/`Task` fires on the subagent's SPAWN acknowledgement — measured across 23 real `Agent` calls in three transcripts, every `tool_result` is a ~310-330 byte "Spawned successfully…" message and NONE carries an `is_error` field; the reviewer's actual report arrives later as a separate task notification this hook never sees. So `dispatch_evidence: observed` means "a reviewer subagent was dispatched", never "returned" or "reviewed", and the `is_error` leg below is currently dead in production — kept because it costs nothing and protects a future payload shape. The subagent tool is named `Agent` on current Claude Code, not `Task` — a `^Task$`-only `PostToolUse` matcher is dead, so the hook and `hooks.json` match `^(Task|Agent)$` (regression: `tests/test-reviewer-evidence-hook.sh`). `.tool_response.is_error` is a TYPED INDEX in jq: it raises on a non-object `tool_response` (an array of content blocks is a plausible agent-output shape), the enclosing `|| exit 0` fires, and the recorder goes permanently silent for every future payload of that shape — read it as `(.tool_response | objects | .is_error)` instead. **General rule: in any `|| exit 0` hook, an unguarded typed index on model-controlled JSON is a silent PERMANENT no-op, not a one-off error** (same test file). The `general-purpose` intent predicate is WORD-BOUNDARY (`*[Rr]eview|*[Rr]eview[!a-zA-Z]*`) and MUST NOT be widened to substring matching: measured against the real dispatch corpus, prefix matching credited 3/9 genuine reviews at 0/7 false positives, word-boundary credits 9/9 at 1/7, and substring also credits 9/9 but at 4/7 — it matches the noun "review(er)" inside implementation task names such as "Task 3: reviewer-evidence writer hook" (same test file). D4's pairing constraint: the hook's write and `scripts/record-review-verdict.sh`'s read must resolve the branch-ledger key IDENTICALLY (regression: `tests/test-review-verdict.sh`). **`branch_ledger_key` hashes `(origin remote URL, branch name)` — NOT the path.** `hooks/lib/branch-ledger.sh` uses `git remote get-url origin` and falls back to the project root ONLY when there is no remote, so path canonicalisation (trailing slash, unresolved symlink) is a non-issue in any repo with a remote, and — measured 2026-09-07 — two worktrees of the same repo on the SAME branch resolve the SAME key. **A worktree split is therefore not by itself a cause of a missed read**, and this bullet previously said it was. The real divergences are (a) **different branch names** — a review recorded on a task branch and a push made from an integration branch, which IS the normal shape of `agent-team-execution`, so the practical warning stands but its cause is the BRANCH, not the directory; and (b) **detached HEAD**, which keys as `detached-<short-sha>` and so CHANGES ON EVERY COMMIT — note this repo's own review-adjudication pattern deliberately uses `git worktree add --detach`. Either miss is safe (falls through to `asserted`, never a fabricated negative), just not the upgrade path those sessions expect. Do NOT cite "a different worktree" as the reason ledger evidence was lost — check whether the BRANCH differed, or whether either side was detached. The classifier arm that matched is stored in the pairing record and the `reviewer-returned` milestone (`arm=allowlist|description`); only `arm=allowlist` with a covering sha credits REVIEW (`push-gate-enforcement.md`, regression `tests/test-reviewer-arm.sh`), the description arm never does, and an unreadable dispatch HEAD is recorded as `-`, never a later HEAD. The resulting `dispatch_evidence` field distinguishes this measured telemetry from an asserted flag and is never a deny predicate — #197's spec forbids any dispatch field from gating, alone or collapsed (regression: `tests/test-review-verdict.sh`). `imported` (from a resolved `--from-github` PR) outranks `observed`, which outranks the caller's own `--dispatch-attempted`/`--dispatch-succeeded` flags — `scripts/record-review-verdict.sh` gates `imported` on the PR having actually RESOLVED, not on the flag alone, since the flag is also `true` when the caller merely passed it (regression: `tests/test-review-verdict.sh`).

## Bullet: "Cross-family egress is enforced at the SENDER, not by a PreToolUse guard ..."

Moved in: the commit named above. Moved, with the test that guards each:

- "measured live 2026-09-16". Guard: `tests/test-egress-consent-hooks.sh` lines 94-95
  (pre-filled `answers` and pre-filled `annotations` are each denied and leave no
  snapshot).
- "found live when two "pick Do not send" dialogs came back approved". Guard:
  `tests/test-egress-consent-hooks.sh` line 102 (approve as the first option is denied)
  and lines 343-344 (the first option must be exactly the decline label).
- "Bisected 2026-09-18: previews of 453/943/1433 chars come back in full (whole string
  or nothing, never truncated), 2413+ do not ⇒ threshold `(1433, 2413]`" and the
  dialog's "(between 943 and 1433 chars)". ("small packages are both, a ~1.4 KB band is
  attested but not fully shown, real packages are neither" was first moved too and is
  back in the rule: without it the sentence's headline, "no package size is both", is
  false for previews under about 1 KB, which LIVE-E2E.md lines 125-129 show were both
  returned and fully visible.) The numbers are kept in the
  comment at `tests/test-egress-consent-hooks.sh` lines 184-191 and in
  `openspec/changes/archive/2026-09-17-egress-consent-dispatcher/LIVE-E2E.md`, which the
  rule still names. Guard for the behaviour: lines 197-244 (the real captured payload
  has `annotations` `{}`; it mints one receipt verified `pre`; an absent key does too;
  the weaker path is announced), lines 278-288 (a matching returned preview records
  `post`; a mismatching one writes no receipt).
- "Before this was understood the hook refused EVERY approval (5 consecutive genuine
  approvals, 0 receipts, 0 declines — indistinguishable from a broken gate), because
  `annotations` arrives as `{}` and the check read that as "unverifiable"." Same guard
  (lines 197-244). Still in force as the rule's instruction not to read `{}` as
  unverifiable.
- "an ask-time veto was tried and depended on a second boundary". Guard:
  `tests/test-consult-dispatch.sh` line 427 (a decline answered before a parallel
  approval wins), line 460 (a parallel decline wins across a second boundary), line 466
  (a re-ask answered after the decline is a valid approval).
- "(the first cut revoked the approval it had just issued)". Guard:
  `tests/test-egress-consent-hooks.sh` lines 357-358 (a duplicate Post keeps the approval
  it issued and claims to revoke nothing).
- "(measured live), and treating one as a turn boundary revoked a genuine approval
  mid-flow". Guard: `tests/test-consult-dispatch.sh` line 488 (a task notification does
  not withdraw the approval), line 494 (control: a real prompt mentioning the tag still
  withdraws).
- "(their summaries are ordinary words and routed to skills nobody asked for)". Guard:
  `tests/test-activation-notification-skip.sh` lines 80-91 (N1 control routes; N2 the
  same summary as a notification routes nothing and writes no state).
- "A lib that sources but breaks jq was the case that mattered: without the retry the
  turn hook KEPT approvals over a user prompt and the activation hook dropped every
  prompt." Guard: `tests/test-activation-notification-skip.sh` lines 154-187 (N8:
  without a lib, and with each broken lib, the activation hook routes and the turn hook
  withdraws, with controls).
- "`hooks/outbound-consent-hook.sh` shipped `100644` in #253, so the harness could
  never execute it and the observer never ran anywhere". Guard:
  `tests/test-hook-file-modes.sh` lines 60-75 (every script `hooks.json` references is
  `100755` in git and executable on disk); `tests/test-egress-consent-hooks.sh` line 434.
- "(a three-read TOCTOU sent unscanned bytes in review)". Guard:
  `tests/test-consult-dispatch.sh` lines 298-308 (H2: a package rewritten mid-send is
  refused or sent unmodified, and the secret never reaches codex). The rule keeps a short
  reason for reading once.
- "is now a payload-first": "now" dropped.

Corrected while moving: in the original, "and renames every unused receipt of the
conversation to `.revoked`" followed the repeated-delivery clause, so it read as if a
repeated delivery revoked receipts. It belongs to "any OTHER answer": a decline calls
`_finish … all` (`hooks/egress-consent-receipt-hook.sh` lines 198-200), which renames
every unused receipt (`egress_revoke_unused` in `hooks/lib/egress-consent.sh`), while a
repeated delivery revokes nothing (`tests/test-egress-consent-hooks.sh` lines 357-358).
The rule now places it there.

Kept in the rule as instructions, reasons or stated limits, whether or not a test also
pins them. No test pins "Why not a guard" (the 60-day measurement is the reason not to
add a destination-keyed deny), the reasoning behind the two argued exceptions, the
limits, the observer's #155 caveat, the Write-tool and jq `test` lessons, or the
negative-corpus pointer.

Still in force: the bullet in the rule.

Original text:

> - **Cross-family egress is enforced at the SENDER, not by a PreToolUse guard (openspec `egress-consent-dispatcher`).** `panel`/`second-opinion` may send only through `scripts/consult-dispatch.sh` (`prepare codex <file>` → `send <digest>`), which refuses unless a fresh (<=900s), unused receipt names the sha256 of the exact frozen package (digest = bytes minus trailing newlines, nothing else normalised — single-sourced in `hooks/lib/egress-consent.sh`). Receipts come from the USER'S ANSWER: `hooks/egress-consent-ask-hook.sh` (PreToolUse `AskUserQuestion`) snapshots a marked question (`[egress-consent:<digest>]`) only if it is clean — it DENIES a marked call whose `tool_input` carries `answers` OR `annotations` (the schema lets the model pre-fill both; measured live 2026-09-16, a genuine ask arrives with only `questions`), a subagent ask, a reused `tool_use_id`, a question whose FIRST (highlighted default) option is the approve label — a reflexive Enter must decline, found live when two "pick Do not send" dialogs came back approved — any other schema violation, or an approve preview that does not hash to the marker; `hooks/egress-consent-receipt-hook.sh` (PostToolUse) consumes the snapshot FIRST (a repeated Post cannot resurrect a spent approval) and writes one receipt only for the exact label `Approve and send` with a HARNESS-RETURNED `annotations[q].preview` that hashes to the digest (never fall back to the model-authored option preview) — **but that preview is SIZE-GATED and for every real package it is simply absent, so the PostToolUse re-check is decorative and the guarantee is PreToolUse-only.** Bisected 2026-09-18: previews of 453/943/1433 chars come back in full (whole string or nothing, never truncated), 2413+ do not ⇒ threshold `(1433, 2413]`, while a frozen consultation package is 4-8 KB. Before this was understood the hook refused EVERY approval (5 consecutive genuine approvals, 0 receipts, 0 declines — indistinguishable from a broken gate), because `annotations` arrives as `{}` and the check read that as "unverifiable". It now records `preview_verified: "pre"|"post"` and ANNOUNCES the weaker path; `pre` rests on the ask hook having hashed the declared preview *before* the question was shown, which is a real chain, just a narrower one. **Sharper still: the DIALOG truncates earlier than the annotation does (between 943 and 1433 chars), so no package size is both fully displayed to the user and attested at Post** — small packages are both, a ~1.4 KB band is attested but not fully shown, real packages are neither. That is a property of the design, not a hook bug; do not "fix" it in the receipt hook. Full bisection: `openspec/changes/archive/2026-09-17-egress-consent-dispatcher/LIVE-E2E.md` (## Handoff); any OTHER answer records a per-digest VETO (the ms the decline was ANSWERED; receipts carry `ask_ms` and the dispatcher skips any asked before it — a question still open when the user said no is void, whatever order parallel answers arrive in; an ask-time veto was tried and depended on a second boundary), a REPEATED delivery of an already-processed answer is ignored (the first cut revoked the approval it had just issued) and renames every unused receipt of the conversation to `.revoked`; asking again about a package withdraws its earlier approval (a cancelled re-ask fires no PostToolUse), and `hooks/egress-consent-turn-hook.sh` (UserPromptSubmit) withdraws all unused approvals, so an approval lives only within its turn — **except for `<task-notification>` prompts: background-task notifications are delivered as `UserPromptSubmit` (measured live), and treating one as a turn boundary revoked a genuine approval mid-flow. The classifier is `hooks/lib/task-notification.sh`, shared with `skill-activation-hook.sh`, which does not route such prompts either (their summaries are ordinary words and routed to skills nobody asked for); without a usable lib (missing, or its jq does not compile, which each hook detects by retrying once with a fallback definition) the turn hook withdraws and the activation hook routes, i.e. each keeps its pre-lib behaviour. A lib that sources but breaks jq was the case that mattered: without the retry the turn hook KEPT approvals over a user prompt and the activation hook dropped every prompt.** Veto records are append-only files (one per decline), and both `send` (after claiming) and the receipt hook (after publishing) re-check them. **Hook file modes:** `hooks/outbound-consent-hook.sh` shipped `100644` in #253, so the harness could never execute it and the observer never ran anywhere; tests calling `/bin/bash <hook>` cannot see this — `tests/test-hook-file-modes.sh` checks every script `hooks.json` references. The dispatcher reads the frozen package ONCE into a private copy (a three-read TOCTOU sent unscanned bytes in review) and runs gitleaks from the isolated dir with `env -u GITLEAKS_CONFIG -u GITLEAKS_CONFIG_TOML --ignore-gitleaks-allow --gitleaks-ignore-path <empty>` — each of those four silenced the scan when measured. **Why not a guard:** measured over 60 days, ~250 cross-family calls and ZERO from these skills (all `/codex:rescue`, direct `codex exec`, proactive `codex-rescue`), so a destination-keyed deny blocks ~all real use; and `codex-rescue` rewrites the prompt, so hashing the Agent prompt binds the wrong object. **Two argued exceptions, both written down in the design:** the dispatcher refuses when it cannot verify (#198 governs phase gates; this is authorisation with a scope of one optional consultation), distinguishing `CANNOT VERIFY` (3) from `NOT APPROVED` (4); and it refuses from day one without a shadow corpus (the affected population measured zero, the refusal costs one re-ask). Escape hatch: `consultation.egress_consent: "warn"` in `~/.claude/skill-config.json`, announced on every send. **Limits, not bugs:** receipt files are agent-writable (defends a SKIPPED ask, not a forged file — an explicit amendment of "never suppress a gate on agent-writable state"); the receipt proves the user approved the supplied preview, not that they read every byte; `-C <empty dir>` is not a filesystem boundary (Codex's read-only sandbox reads anywhere); the Codex stop-time review gate is not a tool call and is uncovered. Identity is strict on both sides — hooks use `session_token_from_transcript` only, the dispatcher `resolve_own_session_token_strict` (added to `session-token.sh`; the non-strict resolver silently returns the singleton, so its output cannot tell "mine" from "another conversation's"). `hooks/outbound-consent-hook.sh` is now a payload-first ADVISORY observer of dispatch that bypasses the dispatcher and writes a text-free corpus to `~/.claude/.egress-bypass-shadow.jsonl` (local companion verbs `status`/`result`/… are silent); it matches command TEXT, so a commit message mentioning `codex exec` is recorded (the #155 class) — discount such records before using the corpus for any deny-flip. PAIRED: the Write tool turns a `\uXXXX` escape into the RAW byte, so a jq `join("\u001f")` written that way ships an invisible 0x1f in source — scan new files with `LC_ALL=C grep $'[\x01-\x08\x0b-\x1f]'`; and jq's `test("\u0000")` is an EMPTY regex that matches everything (it denied every clean ask) — use `explode | any(. == 0)`. Regression: `tests/test-egress-consent-hooks.sh`, `tests/test-consult-dispatch.sh` (receipts minted by the real hooks), `tests/test-egress-consent-lib.sh`, `tests/test-session-token-strict.sh`, `tests/test-outbound-consent.sh`, `tests/test-state-file-cleanup.sh` C7. The 222-prompt negative routing corpus now lives in `tests/probes/negative-corpus/` (probe, not suite).
