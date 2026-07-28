---
type: gotcha
title: Claude Code JSONL `type=="user"` is ~97% not human — filter on promptSource
description: Transcript content readers that select type=="user" ingest tool
  results, hook context, and skill bodies as if they were user input; only
  promptSource=="typed" is genuinely human-authored.
tags: [transcripts, jsonl, mining, provenance, false-signal]
source: measured 2026-07-28 over 497 local session transcripts (242 MB) for this
  repo; pattern anchor scripts/phase-gate-backtest.sh:42-44
timestamp: 2026-07-28T00:00:00Z
---

In `~/.claude/projects/<slug>/*.jsonl`, the `type` field marks the **role slot**,
not the author. Selecting `type=="user"` to mine what a human said returns
overwhelmingly non-human text. Measured over this repo's full history:

| population | count |
|---|---|
| `type=="user"` records | 16,255 |
| carrying `toolUseResult` (tool output) | 13,679 |
| `promptSource=="system"` (hook / skill-injected prose) | 246 |
| `isMeta`, sidechain, other non-human | ~1,600 |
| **genuinely typed by a human** | **468 (2.9%)** |

The contamination is *content-shaped*, so it survives content-based filters and
looks like rich signal. Injected SKILL.md bodies and `UserPromptSubmit` hook
context are long, imperative, and full of "never" / "do not" / "instead" — the
exact vocabulary a correction detector looks for. A naive mine of this corpus
surfaced "corrections" like `never run kubectl commands without` at a suspiciously
uniform frequency; every one was `incident-analysis` playbook prose.

**Filter structurally, on the envelope, not on content:**

- human input: `.promptSource=="typed"` (`"suggestion_accepted"` is also human-chosen)
- exclude: `.toolUseResult != null`, `.isMeta==true`, `.isSidechain==true`
- `<task-notification>` / `<system-reminder>` / `<local-command-*>` still arrive
  as string content under a human `promptSource` — strip by prefix

Existing repo readers are unaffected: `transcript_path` use in
`hooks/lib/session-token.sh` is identity-only, and `phase-gate-backtest.sh:42-44`
keys on `type=="assistant"` + `tool_use` — the correct structural pattern.

Corollary: expect ~1 typed human turn per session. Any transcript-mining plan
should be sized against that, not against raw record counts.

`promptSource` is an internal envelope field, not a documented API — a harness
rename would make this fact silently wrong. The counts above are the tripwire:
re-run the measurement and expect ~3%, not ~100%.

See [[classifier-fixtures-from-real-producer]] — same failure class: a consumer
whose filter was calibrated against an assumed producer shape rather than the
real bytes.
