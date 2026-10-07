# Routing-precision probe (#333)

Instruments for the experiment pre-registered in
`docs/plans/2026-10-05-routing-precision-prereg.md`: does hiding a "sticky repeat" — the
chain's current step re-mandated on a bare reply the session has already been shown —
remove unwanted mandates without hiding work orders, and without the gated steps getting
done less often?

It is a **probe, not a suite test**. Its scripts are tested by
`tests/test-routing-precision-probe.sh`. Its results depend on whose sessions it reads.

## Privacy

`rows.py` writes prompt text. Like the real-prompt replay probe, it refuses to write inside
any git repository or anywhere git cannot vouch for, and writes mode 0600. Report counts,
never prompts. The hook's records (`~/.claude/.sticky-repeat-shadow.d/`, one small file
each) hold no prompt text.

## Stage A — the screen (labels)

```bash
T="$(mktemp -d)"; P=tests/probes/routing-precision
python3 "$P/rows.py" --shadow-log ~/.claude/.sticky-repeat-shadow.d \
    --since <freeze timestamp> --rows "$T/rows.jsonl" --key "$T/key.jsonl"
# two blind labellers and the owner label rows.jsonl with rubric.md; they never see key.jsonl
python3 "$P/score.py" --key "$T/key.jsonl" --labels "$T/a.jsonl" --labels "$T/b.jsonl" --owner "$T/owner.jsonl"
```

`score.py` prints `PASS`, `STOP` or `INCONCLUSIVE`. **PASS sends the rule to stage B. It is
not a licence to turn suppression on**: labels say whether a mandate was warranted, not
what happens once the reminder is gone.

## Stage B — the randomized trial (behaviour)

Run sessions with `ACS_STICKY_REPEAT=trial`. Half of them, chosen by the session token,
hide sticky repeats.

```bash
python3 "$P/trial.py" --shadow-log ~/.claude/.sticky-repeat-shadow.d --since <trial start>
```

It compares, per arm, whether code review and verification were still invoked, whether they
were invoked before the first push attempt, and how often that attempt was denied.

## Runbook: the order to do things in

Nothing here can be hurried. Rows come only from prompts the owner typed, in sessions that
started after the freeze, on a build whose hook writes `rule_version` 3. Headless or scripted
prompts are not typed prompts and are never rows.

```bash
P=tests/probes/routing-precision
LOG=~/.claude/.sticky-repeat-shadow.d
FREEZE="$(git log -1 --format=%cI -- docs/plans/2026-10-05-routing-precision-prereg.md)"
```

**0. Is the instrument live?** The installed plugin's hook must write version 3:
`grep -o '"rule_version":[0-9]*' <installed plugin>/hooks/skill-activation-hook.sh`. An
older build writes records the readers refuse. `$LOG` appears with the first mandated block
of a new session.

**1. Is collection closed?** Stage A is scored once, so check before doing anything else:

```bash
python3 "$P/rows.py" --shadow-log "$LOG" --since "$FREEZE" --count-only
```

The last line says `collection: OPEN` or `collection: CLOSED`. It writes nothing and reads no
label. While it says OPEN, stop here: do not build rows for labelling, do not label, do not
score. It closes at 60 rows the rule would hide, or on 2026-11-16.

**2. Build the rows**, into a private directory outside any repository:

```bash
T="$(mktemp -d)"
python3 "$P/rows.py" --shadow-log "$LOG" --since "$FREEZE" --rows "$T/rows.jsonl" --key "$T/key.jsonl"
```

**3. Two blind labellers.** Each gets `rows.jsonl` and `rubric.md` and nothing else, in its
own context, and writes one line per row, `{"row_id": "...", "label": "..."}`, to `a.jsonl`
and `b.jsonl`. Neither sees `key.jsonl`, the other's labels, the pre-registration or this
file's account of the hypothesis.

**4. The owner's twenty**, drawn by a script so nobody chooses them:

```bash
python3 "$P/owner_sample.py" --rows "$T/rows.jsonl" --labels "$T/a.jsonl" --labels "$T/b.jsonl" --out "$T/owner-rows.jsonl"
```

The owner labels `owner-rows.jsonl` the same way, into `owner.jsonl`, without seeing the
labellers' answers.

**5. Score, once.**

```bash
python3 "$P/score.py" --key "$T/key.jsonl" --labels "$T/a.jsonl" --labels "$T/b.jsonl" --owner "$T/owner.jsonl"
```

Record the whole output on the issue. `STOP` or `INCONCLUSIVE` ends here: the rule stays in
shadow or is removed. `PASS` goes to stage B and is not a licence to suppress.

**6. Stage B**, only after a PASS. The owner sets `ACS_STICKY_REPEAT=trial` in the environment
Claude Code starts with and notes the time as the trial start. It closes at 20 obligations in
each arm or six weeks later. Then:

```bash
python3 "$P/trial.py" --shadow-log "$LOG" --since <trial start>
```

Whatever it reads, making suppression the default is the owner's decision.

## What these cannot tell you

- One owner's sessions. The owner knows the hypothesis.
- Stage B has few units; it can catch a large harm and cannot show there is none.
- The join from a shadow record to its prompt is by session and time (15 s). Records that
  do not join are counted and printed, never dropped silently. The join has only been
  exercised on transcript entries stamped in whole seconds by the tests, not on a real
  transcript.
- Stage B detects a push by the words `git push` / `gh pr merge` in a Bash command and a
  denial by `PUSH GATE` in its result. That over-counts in a repository whose own tests
  contain those words, and nothing shows it does so equally in both arms.
- `prompt_count` in a record stays at 1 under `SKILL_VERBOSE=1`.

## Exit codes

`rows.py`: 0 written, 2 the inputs could not be read, an output path was refused, or the
INSTRUMENT FAULT below.
`score.py`: 0 PASS, 1 STOP, 3 INCONCLUSIVE, 2 the inputs could not be scored.
`trial.py`: 0 no large harm seen, 1 harm, 3 INCONCLUSIVE, 2 the inputs could not be read.

In all three, 2 covers every uncaught failure: an exception must never exit 1, because 1
is a decision.

**Instrument fault.** A "typed" prompt is one the transcript labels with origin `human`
whose text does not start with `<`. If displayed records exist and none joins a typed
prompt, `rows.py` exits 2, writes nothing, and prints what the transcript called the
prompts those records were written for. That is the reader failing to recognise a typed
prompt, not a thin sample.
