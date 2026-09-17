# Real-prompt replay

How often do a skill's triggers fire on real prompts? Held-out rounds and the negative
corpus answer that for prompts someone wrote *for* a test. This probe answers it for the
prompts in your local session transcripts.

It is a **probe, not a suite test**. Its scripts are tested by
`tests/test-real-prompt-replay.sh`. Its results depend on whose transcripts it reads.

## Privacy

The outputs contain your own prompt text. **Every script refuses to write inside any git
work tree** (exit 2), including this repository reached through a symlink or a case-changed
path. Point the outputs at a temporary directory, and never commit or publish the results.
Report counts and classifications, not prompts.

## Run

```bash
T="$(mktemp -d)"
P=tests/probes/real-prompt-replay
python3 "$P/extract.py" --out "$T/prompts.jsonl"
bash "$P/replay.sh" panel "$T/prompts.jsonl" "$T/replay" < /dev/null
python3 "$P/routed.py" --skill panel --since 2026-09-10 --out "$T/routed.jsonl"
bash "$P/replay.sh" panel "$T/routed.jsonl" "$T/replay-routed" < /dev/null
```

The replay takes about 1.5 minutes for 2,000 prompts.

| Script | What it does | Reads |
|---|---|---|
| `extract.py` | Writes the distinct prompts, each labelled by source. | Top-level session transcripts only. |
| `replay.sh` | Tests prompts against one skill's CURRENT triggers, matching the way the hook does. | `config/default-triggers.json` from this checkout, plus a prompts file from either Python script. |
| `routed.py` | Lists the prompts the INSTALLED hook actually routed to a skill, each labelled by source. | The hook output recorded in the transcripts. |

**Sources.** Each prompt is labelled from the transcript's own provenance fields, never from
its wording:

| Label | Meaning |
|---|---|
| `human` | `origin.kind` is `human`: typed, an accepted suggestion, or queued mid-turn. |
| `sdk` | Scripts and pipelines. |
| `peer`, `task-notification`, … | Any other `origin.kind`. |
| `unlabelled` | No provenance fields, for example teammate relays. These are not assumed human. |

Only `human` counts as "a person typed this".

**Excluded:** tool results, subagent transcripts, meta and sidechain entries, and known
wrappers (notifications, resumed-session summaries, injected skill text).

**Limits:**
- Transcripts on disk cover only about four weeks. On 2026-09-17 the earliest was 2026-08-20.
- `replay.sh` measures trigger matches, not selection. It lowercases like the hook (`tr`) and matches like the hook (bash `=~`). It also drops a match that sits inside a word, as the hook does. It does not apply the hook's early exits or scoring.
- `routed.py` reflects whichever plugin version was installed at the time. The hook output does not say which trigger fired. Replaying the routed prompts attributes them to triggers only for the triggers in this checkout.

## Result, 2026-09-17: `panel`

The vendor-free clause (trigger 5) was narrowed and then left alone. Round 7's `pd-5`
("show each one of the reviewers' raw answers verbatim") is a real false dispatch, and so
are similar invented probes. The question was whether the same shape occurs in real use.

**Replay on 2,039 distinct prompts from 46 projects** (587 `human`, 777 `sdk`,
630 `unlabelled`, 45 `peer`):

| | Count |
|---|---|
| Prompts matching any current `panel` trigger | 29 |
| Of those, `human` | **0** |
| Matches per trigger 0–6 | 21, 8, 0, 0, 1, 9, 7 (`human`: all 0) |

All 29 matches came from other sources:
- 26 `sdk`: automated security reviews whose diffs quote this repository's own consultation fixtures. This is the known quoted-content limit, which needs a frame detector rather than a trigger change.
- 3 `unlabelled` relays.

Narrowing trigger 5 with a possessive rule (tried, not shipped) changed the outcome of
none of these prompts. On invented probes it traded new false dispatches and new recall
losses for old ones.

**Live routings since the skill shipped (2026-09-10), made by an older installed plugin:**
10 routings to `panel`, all false.
- 5 followed task notifications. PR #258 stops those.
- 5 followed `human` prompts discussing this routing work. The current triggers match none of those 5.

**Decision:** trigger 5 is unchanged, and `pd-5` stays an open line in
`tests/probes/negative-corpus/`. A false dispatch to `panel` costs an unwanted consent
question, not a send (PR #255).

## Pre-registered revisit: 2026-10-15

Run the four commands above with `--since 2026-09-17` on both Python scripts, on the day.
Transcripts older than about four weeks are deleted, so a later run silently loses the
start of the window.

**1. Check that there is enough evidence.** Both must hold:
- the installed plugin carried the current `panel` triggers for at least 21 days of the window;
- there are at least 200 new `human` prompts.

If either fails, the result is **insufficient evidence**. Record that, and repeat once on
2026-11-12. Do not draw a conclusion from the thinner data.

**2. Count nuisance prompts.** A nuisance prompt is a distinct `human` prompt that:
- is not a consultation request (judged by reading it; record only the count);
- hits trigger 5, either in the replay of all prompts or in the replay of the routed prompts.

**3. Decide.**

| Nuisance prompts | Action |
|---|---|
| 2 or more | Open a fix scoped to the clause that fired, never a whole-skill veto. |
| 1 | Record it, and repeat once on 2026-11-12. |
| 0 | Keep trigger 5 unchanged and close this revisit. |

**No sample-size target.** No `human` prompt hit trigger 5 in 587, so waiting for a set
number of real trigger-5 dispatches could wait indefinitely.

**Report the result as a new dated section here**, with counts and classifications only.
