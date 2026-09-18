# Live end-to-end run — 2026-09-16

The worktree's two `AskUserQuestion` hooks were wired temporarily into the project's
`.claude/settings.local.json` (backed up first; restored byte-identical afterwards) and
driven through the real Claude Code harness with real dialogs. Package: two harmless
lines ("Reply with the single word OK. …"), digest `71e97555…d6ce`.

| # | What was asked | User's answer | Observed | Verdict |
|---|---|---|---|---|
| 1 | approve (approve option listed first) | Approve and send | snapshot → `.used`; receipt written; `send` claimed it (`.consumed`); `codex exec` reached OpenAI and failed on the account's **usage limit** → `MAY HAVE SENT`, exit 5 | chain works end to end; exit-5 path correct |
| 2 | "pick Do not send" (approve listed first) | Approve and send | receipt written | ambiguous user intent → **design change: decline is now the first/default option** |
| 2r | same, retried | Approve and send | receipt written; **not used** | ditto |
| — | approve-first question after the fix | (never shown) | live PreToolUse **deny** `approve-option-first` before any dialog | deny path works live |
| 3 | "pick Other, type the label" (decline first) | Do not send | no receipt — **but the unused approval from 2r was still valid** | **design change: a non-approve answer now revokes earlier unused approvals (latest answer wins)** |
| 4 | same, retried | "Approve and send" + returned preview | receipt written; **not used** | `Other` measurement INCONCLUSIVE — the payload is identical to an option pick |

Additional live measurement (A/B, repeated, flags passed as an array — a zsh
unquoted-scalar loop first produced a false "flags rejected" result):

| `codex exec` from an empty dir | hooks run | MCP servers started | reached model |
|---|---|---|---|
| plain | 18 | yes | yes |
| `--ignore-user-config --disable hooks/plugins/memories/apps` | 0 | no | yes |

The dispatcher now passes those flags; a live `send` through it confirmed 0 hooks / 0 MCP
and a model round-trip (again stopped by the usage limit).

## Second live run — 2026-09-17

| # | What | Observed | Verdict |
|---|---|---|---|
| A | approve a 2-line package (decline listed first) | receipt written at 00:35:48, then **revoked before `send`** — no veto, so not a decline | **defect:** a background-task notification (the Codex review finishing) was delivered as `UserPromptSubmit`; the turn hook took it for the user speaking. Captured payload: `prompt` = the `<task-notification>` block, no other distinguishing field. Fixed: notifications are skipped. |
| A (retry, after the fix at `895f4a0`) | approve | `send` exit 0; Codex answered `OK`; log: `sandbox: read-only`, workdir = the empty `consult-iso.*` dir, **0 hooks, 0 MCP** | **first successful end-to-end send** |
| B | "please choose Do not send" | user chose **Do not send**; one veto record written; `send` exit 4 NOT APPROVED, nothing sent | decline blocks the send, live |

Settings file restored byte-identical after the run. Also found: the dispatcher tests used
the real `TMPDIR` and left ~386 answer directories behind; the test now uses its own.

## Open

- ~~**`Other` free text**~~ — CLOSED 2026-09-18, see below.
- Unused approvals from rows 2r and 4 were left to expire (15 min), never sent.

## Follow-up run — 2026-09-18: the `Other` answer does not exist

Installed plugin 3.89.4, real dialogs, no temporary hooks (the shipped ones are live).
Package: one harmless line ("What is 2+2? Reply with one word."), digest `fc2b4291…da2b`.

| # | What was asked | User's action | Observed | Verdict |
|---|---|---|---|---|
| 1 | approve (decline first), question text asking for "Other" | **clicked** the approve option | snapshot → `.used`; receipt written | control: a click approves, as designed |
| 2 | same package, re-asked | — (ask denied) | PreToolUse **deny** `approve-preview-missing` (the re-ask dropped the preview), and the row-1 receipt became `.revoked` | re-asking withdraws an unused approval even when the new ask is refused |
| 3 | same package, re-asked with the preview restored | typed into **"Chat about this"** | tool call CANCELLED → arrived as a user prompt; no snapshot consumed, no receipt | **there is no free-text answer path** |
| — | `send fc2b4291…` run anyway | — | `NOT APPROVED … nothing was sent` (exit 4) | approving in chat authorises nothing |

**The dialog has no "Other" entry.** The tool description promises one, but the rendered list
held only the two supplied options (screenshot in the session transcript: `1. Do not send`,
`2. Approve and send`). Free text goes to a separate "Chat about this" box, which cancels the
question and is delivered as an ordinary user prompt — so it can never become `answers[q]`,
can never mint a receipt, and, being a prompt, withdraws unused approvals through the turn
hook. The 2026-09-16 inconclusive rows 3–4 are explained: those answers were option picks.

Also observed: the preview pane shows the HIGHLIGHTED option's preview, so it opens on
"No preview available" (decline is first) and the package appears only when the user moves to
the approve option; approving by number never shows it. The receipt attests the approved
OPTION carried the exact package, not that the user read it.

Client-version dependent: re-measure if the dialog ever grows a real free-text entry.

## Handoff — the returned preview depends on SIZE (2026-09-18, for whoever is editing the receipt hook)

Written by session `20842a10` for the session holding uncommitted changes to
`hooks/egress-consent-receipt-hook.sh` + `tests/test-egress-consent-hooks.sh` (the
`_VERIFIED=post|pre` fallback). **Those files were not touched here.** The only files this
session modified are this one and `design.md`, both docs.

**The conflict.** That work rests on "the harness returns annotations as `{}` unless the user
typed a note (measured 2026-09-17), which made every approval unusable". The run above
contradicts the general form: a consent approval on 2026-09-18 returned
`annotations[q].preview`, it hashed to the digest, and the shipped receipt hook wrote a
receipt with no fallback involved.

**What separates the two.** Every `AskUserQuestion` answer in the local transcripts whose
SELECTED option carried a preview (n=13, all CLI 2.1.267, `toolUseResult`):

| preview chars | annotation | kind |
|---|---|---|
| 33 | RETURNED | consent (this session) |
| 191, 224, 276, 335, 374, 384, 431 | RETURNED | plain questions, 2026-09-01 → 09-16 |
| 4097, 4097, 4330, 8437, 8437 | empty | consent, session `da30ec2d`, 2026-09-17 |

Perfect separation by SIZE, not by consent-vs-plain, not by click-vs-navigate, not by client
version. The threshold lies somewhere in (431, 4097] characters. The 2026-09-16 rows 3–4
above ("`Other` INCONCLUSIVE") fit the same rule: those packages were kilobytes.

**Why it matters for the fix.** The premise is right for every REAL package — a frozen
consultation package is 4–8 KB — so the fallback is not a rare degradation, it is the normal
path, and `_VERIFIED=post` will essentially never be reached in production. That is worth
saying out loud in the code and in the threat model: with the preview gone, the evidence that
the approved option carried this exact package rests entirely on the ask hook's snapshot
(which does hash the preview before writing it, so the chain is not broken — but it is now a
PreToolUse-only guarantee, and the receipt's own re-check is decorative for real packages).

**Experiment to pin it** (cheap, one dialog each, no send needed): ask a marked consent
question with the approve option's preview padded to ~500, ~1000, ~2000, ~4000 chars and
record which come back. That bisects the threshold and tells you whether it is a hard cap or
proportional truncation. If it is a cap, a second question worth answering is whether the
dialog SHOWS the full package to the user at those sizes — if the pane truncates too, then no
size of package is both fully shown and fully attested, which is a design fact, not a bug to
patch in the hook.

Raw evidence: `toolUseResult` entries in `~/.claude/projects/*/*.jsonl` (search for
`"annotations"`), and the captured payload at
`tests/fixtures/egress-consent/real-post-payload-2026-09-17.json` (answer
`Approve and send`, approve option preview present, `tool_response.annotations == {}`).

### Answered — the bisection, run 2026-09-18 (session `da30ec2d`)

Both halves of the experiment above were run: padded previews on ordinary (unmarked)
`AskUserQuestion` calls, payloads captured with a temporary `PostToolUse` hook, and the
user asked per question whether an `END-MARKER` line at the bottom of the preview was
visible. Padding was 50-char lines, so "chars" below is the selected option's real
`preview` length.

| preview chars | annotation | end marker visible to the user |
|---|---|---|
| 453 | RETURNED | yes |
| 943 | RETURNED | yes |
| 1433 | RETURNED | **no** |
| 2413 | empty | no |
| ~4000 (option carried no preview; display only) | n/a | no |

**Annotation threshold: (1433, 2413].** Not a proportional truncation — the returned
preview is the full string or nothing (453→453, 943→943, 1433→1433).

**The display truncates EARLIER than the annotation does: between 943 and 1433.** That is
the sharper finding, and it was worth asking: there is a band (~1.4 KB) where the hook CAN
re-check a preview the user could not read in full, and above ~2.4 KB — i.e. every real
4-8 KB package — the package is neither fully shown nor attested at PostToolUse.

So the design fact stands as the handoff predicted: **no package size is both fully
displayed and fully attested.** Small packages are both; the 943-1433 band is attested but
not fully shown; real packages are neither. This is not patchable in the receipt hook, and
the receipt hook no longer pretends otherwise — it falls back to the PreToolUse snapshot
and says so. What the user approves is a question naming a digest plus as much of the
package as the pane renders; what the guarantee rests on is the ask hook having hashed the
full declared preview before the question was shown.

Caveat on the display column: the user reported what was visible in the pane. If the pane
scrolls, "not visible" means "not visible without scrolling", which is the same thing for
an approval decision made at a glance.

Raw payloads: the capture hook wrote them to session scratch (not committed); the
committed sample remains `tests/fixtures/egress-consent/real-post-payload-2026-09-17.json`.
