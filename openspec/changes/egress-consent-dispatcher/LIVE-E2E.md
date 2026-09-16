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

## Open

- **No successful answer has been observed** — Codex's usage limit blocked every send.
  Re-run one approved send after the limit resets.
- **`Other` free text**: whether typing the approve label under "Other" yields a returned
  preview annotation is still unknown. If it does, a typed label is indistinguishable from
  a click; since only the user can type it, this is the user approving, but it should be
  measured, not assumed.
- Unused approvals from rows 2r and 4 were left to expire (15 min), never sent.
