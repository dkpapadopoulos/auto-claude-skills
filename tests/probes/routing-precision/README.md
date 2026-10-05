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

## What these cannot tell you

- One owner's sessions. The owner knows the hypothesis.
- Stage B has few units; it can catch a large harm and cannot show there is none.
- The join from a shadow record to its prompt is by session and time (15 s). Records that
  do not join are counted and printed, never dropped silently. The join has only been
  exercised on transcript entries stamped in whole seconds by the tests, not on a real
  transcript.
- Stage B detects a push by the words `git push` / `gh pr merge` in a Bash command and a
  denial by `PUSH GATE` in its result. That over-counts in a repository whose own tests
  contain those words.
- `prompt_count` in a record stays at 1 under `SKILL_VERBOSE=1`.

## Exit codes

`score.py`: 0 PASS, 1 STOP, 3 INCONCLUSIVE, 2 the inputs could not be scored.
`trial.py`: 0 no large harm seen, 1 harm, 3 INCONCLUSIVE, 2 a usage error.
