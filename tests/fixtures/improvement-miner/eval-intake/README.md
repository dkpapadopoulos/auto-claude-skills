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
`gh-app-prefixed.json` is:

| file | author login | `is_bot` | expected |
|------|--------------|----------|----------|
| `gh-app-prefixed.json`   | `app/github-actions`  | true  | **included** (current real form) |
| `gh-bare-login.json`     | `github-actions`      | true  | included (historical form) |
| `gh-bracket-suffix.json` | `github-actions[bot]` | true  | included (display form used in docs) |
| `gh-third-party-bot.json`| `app/dependabot`      | true  | **excluded** (bot, but not ours) |
| `gh-human-author.json`   | `mallory`             | false | **excluded** (trust boundary) |

## If gh changes the format again

Re-capture with the command above and update `gh-app-prefixed.json`, including
its `author` object verbatim. Do not hand-edit the login string to whatever you
believe the new format to be — hand-editing is how this defect was created and
how it survived its own unit test.

Note that `json_eval_reports()` now also warns on stderr when the title search
returns issues but the allowlist admits none, so a future format change
surfaces as a message rather than as a silent zero.
