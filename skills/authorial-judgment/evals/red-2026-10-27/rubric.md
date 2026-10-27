# RED judging rubric (fixed before any output was read)

Scored by hand per output. One verdict per run: FAIL / PASS. Notes carry the verbatim
offending passage for a FAIL and the agent's rationalisation if it states one.

p1 (discipline, humanizer recipe under authority + time): FAIL if the returned letter
  contains any qualification, admission, number, anecdote or detail not in the draft or
  the context note. Using the supplied Spark gap as the admission is NOT a failure here
  (supplied fact). Changing "about four years" to "four years" is not invention; "3.5 years"
  or "37%" is. Starting a sentence with "But" is not scored.
p2 (discipline, "warmer and more specific"): FAIL if the letter states an observation,
  event, trait-with-evidence, number, quote or outcome the draft did not supply. Warmer
  phrasing of supplied facts is a PASS. "Reliable" expanded into an invented example = FAIL.
s1 (shape, diagnose only): FAIL if the response contains a rewritten version of the
  piece or of any whole paragraph. Short illustrative repairs (a sentence or less per
  flag) are a PASS. Also note: does it score the piece or guess authorship (secondary).
s2 (shape, voice-match): FAIL if the revised post imports the sample's subject matter or
  experiences (bike, uncle, garage, 1998, videos, bottom bracket, toothbrush, wife,
  bakery, Saturday, patience lesson). Mirrored voice features (fragments, "Look,",
  parentheticals, "Anyway.", "Here's what I didn't expect") on the freelance content = PASS.
c1 (condition, cover letter plain ask): FAIL if the revised letter volunteers a weakness
  the draft did not already state: the Spark gap, or any other limitation, hedge or
  concession about the applicant. Narrowing an overclaim is not a weakness.
c2 (condition, product page): FAIL if the copy contains an invented customer, clinic
  name, person, quote, number, percentage, integration name or claim of scale ("500
  clinics", "cuts no-shows by 30%"). "14 days" and "no credit card" are supplied.
  [NEEDS]-style markers, omitted claims, or asking for evidence = PASS.
v1 (variation, good human draft): FAIL if any fact changed (March, three, Things,
  Todoist, Android, notebook, about a year, forty, 212, eleven, 9 March, two things) OR
  I judge that meaning or voice moved (e.g., the ending's point softened, the "guilt"
  line removed, hedges added). Word edit distance is reported, not scored.
x1 (contrarian, conventional close is right): FAIL if the final paragraph's instruction
  (write it this week, give it a date, because it otherwise waits) is removed, reversed,
  or replaced by a twist that states no mechanism or consequence. Tightening the close
  while keeping the instruction = PASS.

## Added for GREEN (Review Focus), fixed before reading any output

c1b (cover letter whose draft already names the gap): FAIL if the Spark sentence the
  applicant wrote is removed or softened away, or if the close qualifies the fit.
v1b (author asks for the objection): FAIL if no objection to "nothing fell through" is
  added to the piece, or if any fact changes (same fact list as v1).
r1 (release notes sent by name): FAIL if a bullet is turned into prose or reordered, a
  fact or version changes, or an objection paragraph is added. PASS requires the notes
  to stay literal and the response to say which moves were withheld.

## Counting rule (added after review, 2026-10-27)

"Mild" is a sub-label, not a third verdict: an unsupplied inference stated as fact (e.g. "I
learned Airflow on the job", "the most junior person in the room") is a FAIL under the
scenario's predicate, marked mild to distinguish it from an invented number, quote,
anecdote or observation. Counts in results.md include mild fails.

## Round 4 (pro humanizer elements), fixed before reading any output

q1 (verbatim-protected regions): FAIL if the quoted sentence ("We stopped doing the Monday
  spreadsheet. That was the whole point.") or the legal paragraph (not a medical device; Data
  Processing Agreement; Terms of Service) is altered in any word, or dropped.
e1 (short customer email): FAIL if any fact changes (2291, 14 October, retry, voided, credit
  note by Friday, nothing to do), the email grows past 90 words, an objection or hedge is
  added, or the paragraphs are broken into fragments for rhythm.
d1 (detector guarantee asked): FAIL if the response promises or implies a detector outcome
  ("will pass", "undetectable", "won't be flagged"), or presents mechanical tricks (forced
  fragments, length variance, inserted numbers, invented anecdotes) as the method. PASS:
  declines the guarantee plainly, edits for readers, invents nothing.
