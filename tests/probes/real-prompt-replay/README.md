# Real-prompt replay

How often do a skill's triggers fire on real prompts? Held-out rounds and the negative
corpus answer that for prompts someone wrote *for* a test. This probe answers it for the
prompts in your local session transcripts.

It is a **probe, not a suite test**. Its scripts are tested by
`tests/test-real-prompt-replay.sh`. Its results depend on whose transcripts it reads.

## Privacy

The outputs contain your own prompt text. **Every script refuses to write inside any git
repository** (exit 2): a work tree or a `.git` directory, reached directly or through a
symlink, a case-changed path or a hard link. A script also refuses when git is missing or
cannot answer. Output files are created with mode 0600. Point the outputs at a temporary
directory, and never commit or publish the results. Report counts and classifications, not
prompts.

This guards against mistakes. It cannot stop another process that swaps a directory for a
symlink between the check and the write.

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
| `routed.py` | Lists the prompts the INSTALLED hook actually routed to a skill, each labelled by source. It also prints the first and last date each plugin version appears in the transcripts. | The hook output recorded in the transcripts. |

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
- `replay.sh` measures trigger matches, not selection. It lowercases like the hook (`tr`) and matches like the hook (bash `=~`). It also drops a match that sits inside a word, as the hook does. It does not apply the hook's early exits or scoring, and it does not model the hook selecting a skill by its name alone.
- `routed.py` reflects whichever plugin version was installed at the time. The hook output does not say which trigger fired. Replaying the routed prompts attributes them to triggers only for the triggers in this checkout.
- A version's date range comes from its install path appearing anywhere in a transcript, including quoted text, so old versions keep appearing after an update. Use the date a version was **first** seen.

## Result, 2026-09-17: `panel`

The vendor-free clause (trigger 5) was narrowed and then left alone. Round 7's `pd-5`
("show each one of the reviewers' raw answers verbatim") is a real false dispatch, and so
are similar invented probes. The question was whether the same shape occurs in real use.

**Replay on 1,996 distinct prompts from 46 projects** (588 `human`, 778 `sdk`,
630 `unlabelled`):

| | Count |
|---|---|
| Prompts matching any current `panel` trigger | 30 |
| Of those, `human` | **0** |
| Matches per trigger 0–6 | 22, 9, 0, 0, 1, 10, 8 (`human`: all 0) |

All 30 matches came from other sources:
- 27 `sdk`: automated security reviews whose diffs quote this repository's own consultation fixtures. This is the known quoted-content limit, which needs a frame detector rather than a trigger change.
- 3 `unlabelled` relays.

Narrowing trigger 5 with a possessive rule (tried, not shipped) changed the outcome of
none of these prompts. On invented probes it traded new false dispatches and new recall
losses for old ones.

**Live routings since the skill shipped (2026-09-10), made by an older installed plugin:**
11 routings to `panel`, all false.
- 6 followed task notifications. PR #258 stops those.
- 5 followed `human` prompts discussing this routing work. The current triggers match none of those 5. The replay does not model selection by skill name, so this does not prove the current hook would stay silent on them.

**Decision:** trigger 5 is unchanged, and `pd-5` stays an open line in
`tests/probes/negative-corpus/`. A false dispatch to `panel` costs an unwanted consent
question, not a send (PR #255).

## Pre-registered revisit: 2026-10-15

On 2026-10-15, run the four commands above with `--since 2026-09-17` on both Python
scripts. Run them on the day: transcripts older than about four weeks are deleted, so a
later run silently loses the start of the window.

**1. Check that there is enough evidence.** Both must hold:
- `routed.py` first saw version 3.89.3 or later on or before 2026-09-24. That is the first release with the current `panel` triggers and PR #258, and the date leaves at least 21 days of the window running it.
- The extract has at least 200 `human` prompts.

**2. Count nuisance prompts.** A nuisance prompt is a distinct `human` prompt that:
- hits trigger 5 in the replay of all prompts;
- is not a consultation request, judged by reading it. Record only the count.

The replay of the routed prompts shows which of them the hook actually dispatched. It does
not change the count.

**3. Decide.**

| Nuisance prompts | Action |
|---|---|
| 2 or more | Open a fix scoped to the clause that fired, never a whole-skill veto. |
| 1 | Hold: record it and repeat once (step 4). |
| 0, with enough evidence | Keep trigger 5 unchanged and close this revisit. |

Not enough evidence also means repeat once (step 4). Do not draw a conclusion from the
thinner data.

**4. The one repeat: 2026-11-12.** Run the same commands with `--since 2026-10-15`. Add its
counts to October's: `human` prompts, nuisance prompts, and days on version 3.89.3 or later.
Decide with the table on the sums.

If the combined evidence is still too thin, or the combined nuisance count is 1, record
that and close the revisit anyway. Trigger 5 stays unchanged, and `pd-5` stays an open
corpus line. There is no second repeat.

**No sample-size target.** No `human` prompt hit trigger 5 in 588, so waiting for a set
number of real trigger-5 dispatches could wait indefinitely.

**Report each run as a new dated section here**, with counts and classifications only.
