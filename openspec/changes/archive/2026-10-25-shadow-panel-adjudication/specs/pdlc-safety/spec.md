# Spec delta: pdlc-safety — panel adjudication of the shadow corpora

> **Not shipped.** Archived 2026-10-25 without applying this delta: both legs were closed INCONCLUSIVE before registration.

## ADDED Requirements

### Requirement: A frozen cohort is the only population a panel decision describes

Each leg's panel cohort MUST be the leg's existing rate population. It MUST be
taken at the leg's adjudicable `predicate_version`, from a corpus snapshot whose
sha256 is recorded in the registering amendment. Episodes whose transcripts were
already lost at registration MUST be excluded from the cohort and listed with
their cause.

The cohort order MUST be a shuffle seeded by the registering commit's sha, and
it MUST be stored in a manifest. Episodes recorded after the snapshot MUST NOT
join the cohort. An episode whose transcript is lost after registration MUST
stay in the cohort as `lost`, reported with its cause.

#### Scenario: A late episode does not enter the cohort
- GIVEN a cohort manifest built from a snapshot
- WHEN a new would-block record is appended to the live corpus
- THEN the manifest and the reader's cohort counts are unchanged

#### Scenario: An episode lost before registration is listed, not counted
- GIVEN an episode in the snapshot whose transcript was deleted before registration
- WHEN the cohort manifest is built
- THEN the episode is absent from the cohort
- AND the manifest lists it as excluded with cause `deleted`

#### Scenario: An episode lost after registration counts against the cap
- GIVEN a cohort episode whose transcript is deleted after registration and is absent from the archive
- WHEN the reader reports the cohort
- THEN the episode is counted under `lost` with cause `deleted`
- AND it counts toward the unknown share

### Requirement: Judges see identical, fixed evidence

The extractor MUST produce one packet per episode, deterministically: the same
inputs MUST give byte-identical output. Each packet MUST carry a coverage manifest
recording what was searched, what was not found, what was truncated, and what
was redacted. The two Claude judges MUST run with no tools, so they cannot read
beyond the packet.

#### Scenario: Extraction is reproducible
- GIVEN the same corpus snapshot, transcript archive and extractor version
- WHEN the extractor runs twice for one episode
- THEN the two packets have the same sha256

#### Scenario: An ambiguous transcript is not guessed
- GIVEN a record whose recorded transcript path is missing and whose basename matches two files
- WHEN the extractor resolves it
- THEN the coverage manifest records `ambiguous`
- AND the packet includes no transcript spans from either file

#### Scenario: A secret in a transcript span does not make the item unsendable
- GIVEN a transcript span that gitleaks flags
- WHEN the extractor builds the packet
- THEN the flagged span is redacted
- AND the coverage manifest records the redaction

### Requirement: A packet establishes an absence only by searching the whole session

Each packet MUST carry a SEARCH section listing every match of the leg's
evidence kinds found from the first line of every surviving copy of the session
up to the push. Matches MUST come only from tool call inputs, user-typed text
and Skill tool results, never from hook output or system reminders. SEARCH MUST
state whether the session's first line, a non-marker line with no parent, was
among the lines searched. The rubric MUST NOT let a judge treat an absence as
established unless SEARCH states that the first line was searched.

#### Scenario: A session searched from its first line with no match
- GIVEN an IMPLEMENT episode whose transcript holds the session's first line and no implementation skill call or `phase_attest`
- WHEN the extractor builds the packet
- THEN SEARCH states that the first line was searched
- AND SEARCH lists zero matches

#### Scenario: A compacted session does not establish an absence
- GIVEN an episode whose transcript and every `.bak` copy begin with a compaction marker
- WHEN the extractor builds the packet
- THEN SEARCH states that the first line was not searched

#### Scenario: A call outside the window still reaches the judges
- GIVEN an IMPLEMENT episode whose `executing-plans` Skill call is 200 events before the push
- WHEN the extractor builds the packet with N = 40
- THEN SEARCH lists that call with its distance from the push

#### Scenario: Hook text naming a skill is not a match
- GIVEN a session whose only mention of `executing-plans` is in a hook's routing hint
- WHEN the extractor builds the packet
- THEN SEARCH lists zero IMPLEMENT matches

### Requirement: Only a unanimous panel produces a substantive label

A panel label MUST be `true_catch` or `false_block` only when all three judges
(two Claude, one Codex) validly return that same label. Any disagreement, and
any judge's `unknown`, MUST yield `unknown`. A missing or twice-invalid response
MUST leave the item `pending`. A valid response MUST NOT be re-run. A `pending`
item MUST be retried on up to three weekly runs and MUST then become `unknown`
with cause `stuck`.

#### Scenario: Codex dissents
- GIVEN both Claude judges return `true_catch` and Codex returns `false_block`
- WHEN aggregation runs
- THEN the episode's panel label is `unknown`

#### Scenario: Quota stops a run midway
- GIVEN Codex fails on an item after both Claude judges answered
- WHEN aggregation runs
- THEN the item is pending and no sidecar row is written for it
- AND the next run asks only Codex, using the stored Claude answers and the same packet

#### Scenario: A stuck item becomes unknown, not missing
- GIVEN an item that is still pending after three weekly runs
- WHEN the third weekly run ends
- THEN the item's panel label is `unknown` with cause `stuck`

### Requirement: Panel labels count only under the amended window with passing controls

The readers MUST count a `claimant: "panel"` row only when both hold:

- its `cohort` equals the leg's registered cohort id;
- the control status for that leg and `panel_config_sha` is `PASS`.

Agent-claimed rows MUST stay excluded. Under an amended window, human-claimed
rows MUST be reported but MUST NOT enter `n`. For both legs, `n` MUST be the
count of `true_catch` plus `false_block`, with `unknown` and `lost` reported
outside it. Band computation MUST go through `hooks/lib/shadow-corpus.sh`.

#### Scenario: Controls have not passed
- GIVEN 29 panel-labelled episodes in the cohort and a control status of `FAIL`
- WHEN the reader runs
- THEN `n` is 0 for the headline rate
- AND the output states that the panel labels are suspended because the controls failed

#### Scenario: A panel row from another cohort
- GIVEN a panel row whose `cohort` is not the registered cohort id
- WHEN the reader runs
- THEN the row is not counted and is reported as excluded with that cause

#### Scenario: Unknowns do not enter n on the REVIEW leg
- GIVEN a REVIEW cohort with 30 `true_catch`, 0 `false_block` and 3 `unknown`
- WHEN the reader runs
- THEN `n` is 30

### Requirement: DENY-eligibility needs completion, the unknown cap, and controls

The reader MUST print DENY-eligible only when all of these hold:

- every cohort item is labelled, `unknown`, or `lost`;
- the headline band is DENY;
- `unknown` plus `lost` is at most 10% of the cohort;
- the repository floor is met over counted episodes;
- the controls have passed.

Otherwise it MUST print which condition failed. The worst-case band (every
`unknown` and `lost` counted as `false_block`) MUST be reported, and MUST NOT
decide eligibility. A cohort not complete by the registered deadline MUST be
reported INCONCLUSIVE. Once eligibility is arithmetically impossible, the runner
MAY stop that leg, and it MUST then report the item at which DENY was ruled out.

#### Scenario: Headline DENY, unknowns over the cap
- GIVEN a complete cohort of 40 episodes, 0 false blocks, and 6 unknowns
- WHEN the reader runs
- THEN the headline band is DENY
- AND DENY-eligible is NOT printed, because 6 of 40 (15%) exceeds the 10% cap

#### Scenario: Headline DENY, unknowns within the cap
- GIVEN a complete cohort of 40 episodes across 2 repositories, 0 false blocks, 4 unknowns, and controls PASS
- WHEN the reader runs
- THEN DENY-eligible is printed
- AND the worst-case band is reported beside it

### Requirement: Planted controls qualify the panel before any real episode

Control episodes MUST be generated by running the real gate in throwaway
repositories, with the shadow logs redirected away from the real corpora. Ground
truth MUST come from the execution manifest, never from a model. Controls MUST
pass through the same extractor and judges as real episodes, and MUST be judged
before any real episode of that leg. Their answer key MUST NOT be readable by
any judge. Control labels MUST NOT be written to a real sidecar. A leg whose
controls fail MUST NOT start its real cohort.

#### Scenario: A control label never reaches the real sidecar
- GIVEN the qualifying round for a leg
- WHEN aggregation runs on its control items
- THEN the real sidecar gains no rows
- AND the control results go to the control store

#### Scenario: Failed controls stop the real cohort
- GIVEN a leg whose control status is `FAIL`
- WHEN the weekly run reaches that leg
- THEN no real episode of that leg is extracted or judged
