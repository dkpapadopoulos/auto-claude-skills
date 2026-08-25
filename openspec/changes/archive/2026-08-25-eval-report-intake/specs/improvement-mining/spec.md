## MODIFIED Requirements

### Requirement: Evidence intake is deterministic and trust-bounded

The evidence bundle SHALL be produced by
`skills/improvement-miner/scripts/mine-evidence.sh` from: committed baseline
files, structured GitHub issue bodies authored by the repository's GitHub
Actions bot, live `scripts/gate-status.sh` output when present, auto-memory
frontmatter index lines, and owner-authored `improvement-miner-run` ledger
issues. The script SHALL never request issue comments, raw workflow-artifact
fields, or `tests/fixtures/*/evals/` content.

The author allowlist SHALL be evaluated against a **normalised** login — the
reported login with a leading `app/` and a trailing `[bot]` removed — and SHALL
NOT be pinned to any single literal spelling. `gh` has reported this identity
as `app/github-actions`, `github-actions`, and `github-actions[bot]`; a filter
naming one of these admits nothing when the tool reports another, and that
failure is silent.

The allowlist SHALL additionally require `.author.is_bot == true`. An absent
`is_bot` field MUST be treated as a rejection, not as an unknown to be
tolerated, so that a change in the shape of `.author` fails closed.

The title-prefix test SHALL verify that the title is a string before applying
the prefix comparison, in both the filter and any derived count. A non-string
title MUST cause only that issue to be excluded and MUST NOT abort the bundle.

Expectation provenance: discovery brief conditions 2 and 6 (F2 public repo, F7
raw-artifact adversarial text), assumption A6; issue #203.

#### Scenario: non-allowlisted author is excluded

- GIVEN a GitHub issue whose title matches the eval-regression pattern but
  whose author is not the repository's GitHub Actions bot
- WHEN `mine-evidence.sh bundle` runs
- THEN that issue's content does not appear anywhere in the bundle

#### Scenario: comments are never requested

- GIVEN any bundle or ledger read
- WHEN the script calls `gh`
- THEN the requested JSON field list contains no comment fields

#### Scenario: every reported spelling of the bot login is admitted

- GIVEN an eval-regression issue authored with `is_bot` true and a login of
  `app/github-actions`, `github-actions`, or `github-actions[bot]`
- WHEN `mine-evidence.sh bundle` runs
- THEN the issue appears in `eval_reports[]` in each case

#### Scenario: a non-bot account holding the bot's name is excluded

- GIVEN an eval-regression issue whose login normalises to the allowlisted
  name but whose `is_bot` is false, or whose `is_bot` field is absent
- WHEN `mine-evidence.sh bundle` runs
- THEN the issue is excluded and its body appears nowhere in the bundle

#### Scenario: a malformed title does not abort the run

- GIVEN a response containing one issue from the allowlisted bot whose title is
  not a string, alongside a well-formed eval-regression issue from that bot
- WHEN `mine-evidence.sh bundle` runs
- THEN the bundle is produced successfully, the well-formed issue appears in
  `eval_reports[]`, and the malformed one does not

## ADDED Requirements

### Requirement: An empty eval intake announces its cause

An intake that admits nothing is indistinguishable downstream from a repository
that has no eval regressions. When the intake admits nothing while candidates
existed, the script SHALL emit a diagnostic on stderr naming the cause it has
actually established, and SHALL NOT attribute the outcome to a cause it has not
checked.

Because the causes carry different remedies, they SHALL be reported separately:
rejection by the author allowlist directs the reader to re-capture the author
fixture, while a search that matched no correctly-titled issue directs the
reader to the title prefix. Diagnostics SHALL be written to stderr only, so the
bundle's stdout remains parseable JSON.

These diagnostics are advisory and MUST NOT abort the run: a repository whose
only issues under this title prefix are human-authored is a legitimate steady
state, and making it fatal would create pressure to relax the trust boundary in
order to restore the tool.

`SKILL.md` SHALL instruct the model to surface these diagnostics and SHALL
state that an empty `eval_reports[]` accompanied by one of them is not evidence
that no eval regressions exist.

#### Scenario: correctly-titled issues rejected by the author allowlist

- GIVEN one or more issues whose titles start with the eval-regression prefix
- AND every one of them fails the author allowlist
- WHEN `mine-evidence.sh bundle` runs
- THEN stderr names the author allowlist as the cause and points at the author
  fixture
- AND stdout remains parseable JSON

#### Scenario: the search matched but no title has the expected prefix

- GIVEN the title search returns at least one issue
- AND no returned issue's title starts with the expected prefix
- WHEN `mine-evidence.sh bundle` runs
- THEN stderr reports the title-prefix mismatch, states that an unrelated issue
  merely mentioning the phrase is benign, and names a renamed generator as the
  alternative reading
- AND the diagnostic does not blame the author allowlist

#### Scenario: a genuinely empty search is silent

- GIVEN the title search returns no issues at all
- WHEN `mine-evidence.sh bundle` runs
- THEN no eval-intake diagnostic is emitted

### Requirement: Intake fixtures are captured from the real producer

Fixtures pinning the author allowlist SHALL be derived from a recorded `gh`
response rather than hand-written, and SHALL carry provenance: the capture
command, the date, and the `gh` version. A hand-written fixture proves only
that the filter agrees with the test author's belief about the tool's output
format, which is how the #203 defect passed its own unit test for the skill's
entire life.

Where a fixture's `body` is replaced to bound the committed size, the
substitution SHALL be stated in the provenance record, and the field under test
SHALL be preserved verbatim.

#### Scenario: the author form under test is real

- GIVEN the fixture that pins the current author form
- WHEN its provenance record is read
- THEN it names the capture command, date, and `gh` version, and the `author`
  object is verbatim from that capture
