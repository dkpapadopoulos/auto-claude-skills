## Why

`improvement-miner`'s eval-report intake matched nothing, on every run, for the
skill's entire life.

`json_eval_reports()` in `skills/improvement-miner/scripts/mine-evidence.sh`
compared `.author.login` to the literal `github-actions`. `gh` (2.97.0) returns
`app/github-actions`. The filter therefore admitted zero issues, and
`eval_reports[]` was empty in every bundle regardless of how many eval
regressions existed.

Three consequences, all silent:

1. `eval_reports[]` is the miner's only **end-user-facing** evidence channel.
   With it dead, the `no_end_user_facing` warning emitted by the selection gate
   described a property of the script, not of the repo.
2. Open behavioral-eval regression **#94** (`incident-analysis`) was never
   surfaced by any mine.
3. The kill criterion — which decides whether the skill is decommissioned — was
   being scored against a miner running with one input disconnected. A low
   approval rate would have been attributed to the skill's judgment.

The defect survived its own unit test. `test_eval_reports_author_allowlist`
hand-wrote its fixture as `"login": "github-actions"`, so it only ever proved
the filter agreed with the test's own idea of gh's output format — never with
gh's actual output. A code comment confidently defended the wrong literal and
warned against "fixing" it to a third form that was also wrong.

The canonical spec encoded the same error: it named the allowlist
`github-actions[bot]`, the display form, which matches nothing either.

## What Changes

- The author allowlist matches a **normalised** login (strip a leading `app/`,
  a trailing `[bot]`) rather than any single literal, ANDed with
  `.author.is_bot == true` so widening the accepted spellings does not widen
  the trust boundary.
- `is_bot` is required, not merely tolerated: `== true`, never `!= false`. The
  `app/` and `[bot]` spellings are unforgeable in GitHub logins, so bare
  `github-actions` is the only forgeable spelling and `is_bot` is its sole
  guard.
- The title-prefix test is **type-safe** in both the filter and the diagnostic
  count. Previously a non-string title on an allowlisted bot's issue aborted
  the whole bundle (exit 5) and misreported it as unparseable JSON.
- Two advisories where the intake admits nothing: one naming the author
  allowlist (when correctly-titled issues were rejected), one naming the title
  prefix (when gh's phrase-contains search matched but no title had the
  prefix). A silently-empty intake is indistinguishable from "no regressions".
- Fixtures are captured from the real producer, one per author form, with
  recorded provenance — including negative cases for impersonation, an absent
  `is_bot`, and non-string titles.

## Capabilities

### Modified Capabilities

- `improvement-mining`: the evidence-intake requirement now specifies the
  normalised-login + `is_bot` allowlist, type-safe title handling, and the
  non-silence obligation when the intake admits nothing.

## Impact

- `skills/improvement-miner/scripts/mine-evidence.sh` — `json_eval_reports()`.
- `skills/improvement-miner/SKILL.md` — Step 1 must surface the advisories and
  must not read `eval_reports: []` as "no eval regressions".
- `tests/test-improvement-miner.sh` and
  `tests/fixtures/improvement-miner/eval-intake/` (new).
- No hook, config, routing table, or phase-enforcement path is touched. The
  script is user-invoked and is correctly absent from `_GATE_ENFORCE_LIBS`.

**Trust-boundary note.** Before this change the accidentally-empty filter meant
no externally-authored body ever reached the model through this channel. The
prompt-injection surface the SKILL.md describes becomes real for the first
time: the admitted `body` is externally authored and is fed to the model as
evidence. That is the designed boundary, but it is now load-bearing rather than
vacuous, and the human approval gate before `gh issue create` is doing more
work than it was. `hooks/publish-guard.sh` remains a confidentiality control
over verbatim reproduction; it does not constrain what an injected body can
steer the model to do.
