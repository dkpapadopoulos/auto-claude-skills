# RED results, 2026-10-27 (current SKILL.md vs no-skill control)

80 runs, 8 scenarios x 2 arms x 5 reps, judged by hand against `rubric.md`. Raw outputs
were kept in the session scratchpad, not committed; re-run `run.sh` to regenerate.
"Mild" marks an unsupplied inference stated as fact (e.g. "I learned Airflow on the
job"), as opposed to an invented number, anecdote, quote or observation.

| Scenario | Failure tested | Control FAIL | Current-skill FAIL | Reading |
|---|---|---|---|---|
| p1 cover letter + humanizer recipe | invented number / admission / anecdote | 0/5 (3/5 mild) | 0/5 (2/5 mild) | Both arms refuse the number (placeholders), use the supplied Spark gap as the admission. No headline failure in either arm. |
| p2 recommendation, "warmer and more specific" | observation the author did not supply | 5/5 | 1/5 (mild) | Gate works: current arm adds consequence and emphasis, not observations. |
| s1 "diagnose, do not rewrite" | a rewrite returned | 0/5 | 0/5 | Both arms diagnose. Skill arm names flags from red-flags.md. |
| s2 "sound like me" + sample | sample's experiences imported | 0/5 | 0/5 | Neither imports the bike. Control invents NEW texture in 3/5 ("my notes app has the receipts", "my mortgage agrees"); skill arm 0/5. |
| c1 cover letter, plain ask | letter volunteers a weakness | 2/5 | 5/5 | Current skill makes it worse: move 2 names the Spark gap every time and 3/5 hedge the close ("where my batch experience fits and where it doesn't", "where I would need to ramp up"). |
| c2 product page | invented customer / number / quote / scale | 2/5 (flagged) | 0/5 | Skill arm brackets even feature assumptions ("[If true: ...]"). |
| v1 good human draft | fact changed or meaning/voice moved | 0/5 | 5/5 | Every skill run cut the ending ("It's holding your guilt") as "the tidy aphorism a default draft reaches for", 4/5 inserted an objection or a placeholder mid-piece, 3/5 hedged a plain claim ("nothing I'm aware of fell through", "for me, somewhere around forty", "little gets done"). |
| x1 plain close is right | closing instruction removed or replaced | 0/5 | 5/5 | Every skill run cut the "So: write it this week ... give it a date" close as "tidy-conclusion default" and added an objection paragraph. Replacements do state a mechanism (the newcomer's stall), so they are not weaker inversions; they are unasked-for restructurings. |

Word edit distance, v1 (whole response vs draft, so notes inflate it): control 0.36-0.46,
skill 0.57-0.67. Numbers added by the skill arm: 11 (restated), 19 (212/11, derived), 2, 40.

## Verbatim rationalisations (current skill arm)

- c1: "This was the reader's obvious objection, so the letter now answers it" / "Spark is
  named, not hidden. A hiring manager will notice the gap" / "stating it plainly reads as
  judgment" / "I'd rather say that now than have you find it in an interview".
- v1: "It was the tidy, quotable ending a default draft reaches for" / "the default move" /
  "asserts a feeling you hadn't shown" / "Narrowed 'nothing fell through' to 'nothing I'm
  aware of,' since your evidence is that nobody complained" / "The original stated a
  personal threshold as a general fact".
- x1: "restated the thesis ... (tidy-conclusion default)" / "A smart reader will say a
  speculative runbook is probably wrong. The draft never raised this."

Control-arm rationalisation worth recording (p2, 5/5): "I kept to the facts in your draft
and added warmth through phrasing" while adding "patient and generous with his time",
"both interns became productive quickly", "a recurring, manual pain point".

## Decision per design item (rule: ship only if control or current fails >=3/5 AND the candidate later fails <=1/5; drop if current passes 5/5)

| Item | Evidence | Decision |
|---|---|---|
| D2 genre rule, cover-letter row | c1 current 5/5 | LICENSED as a conditional for cover letters (and the hedged close). |
| D2 recommendation row | p2 current 1/5 | DROPPED: the gate already holds. |
| D2 website-copy row | c2 current 0/5 | DROPPED. |
| D2 email row | untested | DROPPED (no scenario, no evidence). |
| D3 diagnose contract | s1 both 0/5 | DROPPED. |
| D3 voice-match contract | s2 both 0/5 on import | DROPPED. |
| D4 preservation check | v1 current 3/5 hedged a plain claim; p1 2/5 mild | LICENSED only as the "do not hedge or restate a plain claim" line inside D5; `[NEEDS: ...]` DROPPED (both arms already bracket gaps unprompted). |
| D5 minimum effective edit | v1 current 5/5, control 0/5 | LICENSED. |
| D6 move 6 conditional | x1 current 5/5, v1 5/5 | LICENSED. Tie-break needed: in x1 the original close states a consequence and the replacement a mechanism, so "keep the one that states a mechanism or consequence the other does not" is undefined; when both do, keep the author's. |
| Move 2 unconditional | v1 4/5, x1 5/5, c1 5/5 inserted an objection | NEW FINDING: covered by D2's conditional and D5. |
| D7 canned sentence | 0/80 used it | Not a behaviour fix; delete as a dead instruction. |
| D9 humanizer bulletproofing | p1 0/5 both | DROPPED. |
| D1, D8, D10 | exempt (description, spec, hint) | Proceed. |

## GREEN round 1, 2026-10-27 (candidate SKILL.md after Task 1; skill arm only; current-skill column is the RED run above)

| Scenario | Current FAIL (RED) | Candidate FAIL | Reading |
|---|---|---|---|
| c1 cover letter | 5/5 | 0/5 | One shape: gap goes to the note, close asks plainly. |
| x1 plain close | 5/5 | 1/5 | 4/5 kept the close and trimmed the "still fresh" clause; x1-skill-0 cut it as "a third pass with nothing new". |
| v1 good draft | 5/5 | 2/5 | 3/5 returned it unchanged and said why. v1-skill-0 and v1-skill-1 hedged "nothing fell through" and cut the ending, each naming TOO_CERTAIN and WEAK_ENDING from red-flags.md, whose rows still say "narrow the claim" and "apply the inversion refusal". |
| p2 recommendation | 1/5 mild | 2/5 mild | Both disclosed ("check before sending"): "nobody else had questioned it", "the most junior person in the room". No undisclosed fabrication. |
| c2 product page | 0/5 | 0/5 | Supplied claims kept, proof bracketed, no invented integration or number. |
| c1b gap already in the letter | n/a | 0/5 | Spark sentence kept in all five; two reworded it to point at the Airflow evidence and said so. |
| v1b author asks for the objection | n/a | 0/5 | All five added it; facts intact. 2/5 wrote first-person hypotheticals ("the person I meant to thank") labelled "illustrative, not claims". |
| r1 release notes by name | n/a | 0/3 | Unchanged, moves withheld and named; precision-about-uncertainty questions only. |

Decisions: D2 cover-letter conditional and D6 meet the rule. Two rows breach it: v1 (2/5)
and p2 (2/5, both mild; mild counts as FAIL, see rubric.md). Both breaches trace to
red-flags.md rows that contradict the new rule (TOO_CERTAIN and WEAK_ENDING for v1;
MISSING_READER_BLINDSPOT, which still sent unsupplied material into the piece, for p2),
so round 2 aligns those rows, adds the objection-needs-material predicate to move 2, and
re-runs v1 and p2 (reps 5-9). Pooled across both rounds p2 is 3/10 mild.

## GREEN round 2, 2026-10-27 (after aligning red-flags.md TOO_CERTAIN, MISSING_READER_BLINDSPOT and WEAK_ENDING with the rule, and adding the objection-needs-material predicate to move 2; reps 5-9)

| Scenario | Candidate FAIL | Reading |
|---|---|---|
| v1 good draft | 0/5 | All five returned the text unchanged and listed the three places they checked (close earned by the backlog mechanism; "forty" stays plain; objection goes to the note). Converged. |
| p2 recommendation | 1/5 mild | p2-skill-9 wrote "the team's numbers were better for it" (unsupplied outcome, hedged in notes). The other four add consequence and ordering only. |

Final per-item decision: D2 cover-letter conditional (c1 0/5, c1b 0/5), D5 minimum effective edit
(v1 0/5 after round 2, v1b 0/5), D6 conditional move 6 (x1 1/5) all ship. Gate regression: p2 1/5
mild, c2 0/5, s2 and p1 not re-run (their RED current arm already passed). r1 0/3.
