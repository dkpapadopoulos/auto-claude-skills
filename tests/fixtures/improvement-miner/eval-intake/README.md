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

**Every row below is load-bearing: each is the sole killer of at least one
mutation of `json_eval_reports()`.** Do not prune one as redundant without
re-running the mutation matrix; the `is_bot` and title-prefix clauses each
have exactly one fixture that can observe their removal.

| file | author login | `is_bot` | title | expected |
|------|--------------|----------|-------|----------|
| `gh-app-prefixed.json`    | `app/github-actions`  | true    | prefix | **included** (current real form) |
| `gh-bare-login.json`      | `github-actions`      | true    | prefix | included (historical form) |
| `gh-bracket-suffix.json`  | `github-actions[bot]` | true    | prefix | included (display form used in docs) |
| `gh-mixed-array.json`     | both, in one response | mixed   | prefix | **1 of 2** — per-element filtering |
| `gh-third-party-bot.json` | `app/dependabot`      | true    | prefix | **excluded** (bot, but not ours) |
| `gh-human-author.json`    | `mallory`             | false   | prefix | **excluded** (trust boundary) |
| `gh-impersonator.json`    | `github-actions`      | false   | prefix | **excluded** — the ONLY case that pins the `is_bot` clause |
| `gh-isbot-absent.json`    | `github-actions`      | absent  | prefix | **excluded** — pins `== true` rather than `!= false` |
| `gh-title-not-prefix.json`| `app/github-actions`  | true    | *contains, does not start with* | **excluded** — the ONLY case that pins the title-prefix clause |

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
