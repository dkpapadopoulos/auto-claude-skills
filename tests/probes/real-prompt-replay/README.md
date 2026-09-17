# Real-prompt replay

How often do a skill's triggers fire on the language a user actually types? Held-out
rounds and the negative corpus answer that for prompts someone wrote *for* a test. This
probe answers it for prompts from real sessions, read from your local transcripts.

It is a **probe, not a suite test**. Its scripts are tested by
`tests/test-real-prompt-replay.sh`. Its results depend on whose transcripts it reads.

## Privacy

The outputs contain your own prompt text. **Every script refuses to write inside this
repository** (exit 2). Point `--out` / the output directory at a temporary directory, and
never commit or publish the results; report counts and classifications, not prompts.

## Run

```bash
T="$(mktemp -d)"
python3 tests/probes/real-prompt-replay/extract.py --out "$T/prompts.jsonl"
bash tests/probes/real-prompt-replay/replay.sh panel "$T/prompts.jsonl" "$T/panel" < /dev/null
python3 tests/probes/real-prompt-replay/routed.py --skill panel --since 2026-09-10 --out "$T/routed.tsv"
```

The scripts do three different jobs:

| Script | What it does | Reads |
|---|---|---|
| `extract.py` | Writes the distinct prompts a person typed. | Top-level session transcripts only. |
| `replay.sh` | Tests every extracted prompt against one skill's CURRENT triggers, using the hook's own bash `=~` matching. | `config/default-triggers.json` from this checkout, plus the extracted prompts. |
| `routed.py` | Lists what the INSTALLED hook actually routed to a skill, and splits the prompts it followed into human and non-human. | The hook output recorded in the transcripts. |

What `extract.py` excludes:
- tool results;
- subagent transcripts;
- task notifications and resumed-session summaries;
- injected skill text;
- duplicates.

Limits of the replay:
- It measures **trigger matches, not selection**. The hook's early exits and scoring are not applied.
- `routed.py` reflects whichever plugin version was installed at the time.

## Result, 2026-09-17: `panel`

The vendor-free clause (trigger 5) was narrowed and then left alone. Round 7's `pd-5`
("show each one of the reviewers' raw answers verbatim") is a real false dispatch, and so
are similar invented probes. The question was whether the same shape occurs in real use.

**Replay on 2,015 distinct prompts from 45 projects:**

| | Count |
|---|---|
| Prompts matching any current `panel` trigger | 28 |
| Matches per trigger 0–6 | 21, 8, 0, 0, 1, 8, 7 |
| Matching prompts that were typed by a person | **none** |

The 28 matches are all automated:
- 24 security-review prompts whose diffs quote this repository's own consultation fixtures (the known "quoted content" limit, which needs a frame detector rather than a trigger change);
- 3 messages from other sessions;
- 1 prompt from a scheduled pipeline.

Narrowing trigger 5 with a possessive rule (tried, not shipped) changed the outcome of **none** of the 2,015 prompts. On invented probes it traded new false dispatches and new recall losses for old ones.

**Live routings since the skill shipped (2026-09-10), made by an older installed plugin:** 11 routings to `panel`, all false.
- 5 followed non-human input, mostly task notifications. PR #258 stops those.
- 6 followed prompts discussing this routing work. The current triggers match **none** of those 6.

**Decision:** trigger 5 is unchanged, and `pd-5` stays an open line in
`tests/probes/negative-corpus/`. A false dispatch to `panel` costs an unwanted consent
question, not a send (PR #255).

## Pre-registered revisit: 2026-10-15

Re-run all three commands after the installed plugin has carried the current triggers
for about four weeks.

- **Open a fix if either happens.** A *human-typed* prompt appears that:
  - matches trigger 5 and is not a consultation request; or
  - is routed live to `panel` by trigger 5 and is not a consultation request.

  The fix is scoped to the clause that fired, never a whole-skill veto.
- **Keep trigger 5 unchanged** if no such prompt appears.
- **No sample-size target.** With zero vendor-free matches in 2,015 prompts, a target
  number of vendor-free selections would never be reached for this workload, so the
  decision uses the budget above.
- **Report the result as a new dated section here**, with counts and classifications only.
