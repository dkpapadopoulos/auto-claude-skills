# eval-intake fixtures (issue #203) — NEVER DELETE

Captured `gh issue list` responses used to pin `json_eval_reports()`'s author
allowlist in `skills/improvement-miner/scripts/mine-evidence.sh`.

## Why these exist

Before #203 the allowlist compared `.author.login` against the literal string
`github-actions`. `gh` returns `app/github-actions`, so the filter matched
nothing and `eval_reports[]` was empty on every run — the miner's only
end-user-facing evidence channel, silently dead, with an open regression
(#94) invisible to it the whole time.

The unit test that covered this code passed throughout, because it
**hand-wrote** the fixture as `"login": "github-actions"`. It proved the
filter agreed with the test's own idea of gh's output format, never with
gh's actual output. See `.claude/knowledge/classifier-fixtures-from-real-producer.md`.

## Provenance

`gh-app-prefixed.json` is derived from a real capture, not hand-written:

```
gh issue list --state all --limit 50 \
   --search '"Behavioral eval regression" in:title' \
   --json number,title,body,author
```

- captured: 2026-08-24
- `gh version 2.97.0 (2026-07-31)`
- repo: `dkpapadopoulos/auto-claude-skills`
- the `author` object — the field under test — is **verbatim** from that capture,
  including `is_bot`.
- the `body` field is replaced with the marker `REAL-BOT-BODY-MARKER`; the real
  body is ~9.6 KB of eval report and nothing in the allowlist reads it. Titles
  and issue numbers are verbatim.

The other files are constructed variants covering forms the capture cannot
contain at once. They are explicitly NOT the authority on gh's format —
`gh-app-prefixed.json` is.

**Five of these are the sole killer of some mutation — deleting one silently
removes the only coverage of a clause.** The rest are covered but never alone.
That distinction is measured, not asserted; an earlier version of this file
claimed *every* row was a sole killer, which was false for four of them and is
exactly the confidently-wrong-documentation failure this directory exists to
prevent. Re-run the matrix before pruning anything.

| sole killer of a mutation | never alone |
|---|---|
| `gh-bracket-suffix` (the `[bot]` strip) | `gh-app-prefixed` |
| `gh-isbot-absent` (`== true` vs `!= false`) | `gh-bare-login` |
| `gh-title-not-prefix` (the title clause; the title NOTE) | `gh-human-author` |
| `gh-null-title-with-drift` (the `.title?` type guard) | `gh-impersonator` |
| `gh-numeric-title` (the cannot-count branch) | `gh-mixed-array` |
| | `gh-third-party-bot` |

`gh-app-prefixed` being in the right-hand column does NOT make it prunable —
it is the only file that is ground truth about gh's actual output format, and
its value is provenance rather than mutation coverage. `gh-human-author` and
`gh-impersonator` are rejected by more than one clause each, so no single-clause
mutation can isolate them; they are defence in depth.

| file | author login | `is_bot` | title | expected |
|------|--------------|----------|-------|----------|
| `gh-app-prefixed.json`    | `app/github-actions`  | true    | prefix | **included** (current real form) |
| `gh-bare-login.json`      | `github-actions`      | true    | prefix | included (historical form) |
| `gh-bracket-suffix.json`  | `github-actions[bot]` | true    | prefix | included (display form used in docs) |
| `gh-mixed-array.json`     | both, in one response | mixed   | prefix | **1 of 2** — per-element filtering |
| `gh-third-party-bot.json` | `app/dependabot`      | true    | prefix | **excluded** (bot, but not ours) |
| `gh-human-author.json`    | `mallory`             | false   | prefix | **excluded** (trust boundary) |
| `gh-impersonator.json`    | `github-actions`      | false   | prefix | **excluded** (trust boundary; rejected by two clauses) |
| `gh-isbot-absent.json`    | `github-actions`      | absent  | prefix | **excluded** — pins `== true` rather than `!= false` |
| `gh-title-not-prefix.json`| `app/github-actions`  | true    | *contains, does not start with* | **excluded** — pins the title-prefix clause and the title NOTE |
| `gh-null-title-with-drift.json` | `mallory`, then a drifted bot | mixed | *null*, then prefix | **excluded**, and must still WARN — pins the `.title?` type guard |
| `gh-numeric-title.json`   | `mallory`, then a drifted bot | mixed | *numeric*, then prefix | **excluded**, and must warn *cannot count* — pins that branch |

Why the last three exist: `app/` and `[bot]` are unforgeable (GitHub logins
admit neither `/` nor `[`), so bare `github-actions` is the only spelling a
human could hold and `is_bot` is its sole guard. `!= false` would admit an
*absent* field — and this entire issue was gh changing the shape of `.author`,
so the clause must require the field, not merely tolerate it. Separately,
gh's `in:title` search is phrase-CONTAINS, not prefix, so `startswith` is what
narrows the search to genuinely eval-shaped reports.

## If gh changes the format again

Re-capture with the command above and update `gh-app-prefixed.json`, including
its `author` object verbatim. Do not hand-edit the login string to whatever you
believe the new format to be — hand-editing is how this defect was created and
how it survived its own unit test.

Note that `json_eval_reports()` now also warns on stderr when the title search
returns issues but the allowlist admits none, so a future format change
surfaces as a message rather than as a silent zero.
