# Delta Spec: behavioral-evaluation — scheduled LLM-judged pack runs

## ADDED Requirements

### Requirement: Judge assertion kind

The behavioral eval runner SHALL support an assertion kind `judge` whose verdict is produced by a pinned judge model invoked with all tools disallowed and strict JSON output. The runner MUST NOT treat an unparseable judge response as a pass: after one retry it SHALL record the assertion as FAIL with detail `judge-unparseable`. The judge prompt MUST wrap subject output as data-only with an injection-defense preamble.

#### Scenario: Judge assertion evaluates semantic criteria

- GIVEN a scenario with an assertion `{"kind": "judge", "criteria": "..."}`
- WHEN the runner executes the scenario
- THEN a second sandboxed `claude -p` call with the pinned judge model SHALL score the subject output against the criteria
- AND the assertion SHALL pass if and only if the judge returns `{"verdict": "pass"}`

#### Scenario: Unparseable judge output fails loudly

- GIVEN a judge invocation that returns non-JSON or JSON without a `verdict` field twice (initial + one retry)
- WHEN the runner records the assertion result
- THEN the assertion SHALL be recorded FAIL with detail `judge-unparseable`
- AND the iteration artifact SHALL contain the raw judge response for diagnosis

### Requirement: Pack-level runner with baseline regression detection

A pack runner SHALL execute every scenario of a behavioral pack at a configured variance, aggregate per-assertion pass rates from iteration artifacts, classify them (stable ≥90%, flaky 50–89%, broken <50%), and compare classifications against a committed baseline. It SHALL exit 1 when any assertion's classification worsens relative to baseline, and exit 2 when a baseline scenario id is absent from the pack (never-delete guard). Scenarios tagged `"safety": true` SHALL be hard gates: any failed iteration on any gated assertion of a safety scenario SHALL be reported as a regression regardless of aggregate pass rate. An assertion within a safety scenario MAY be marked `"gate": false` to be excluded from the hard gate while remaining measured, classified, and baseline-compared; assertions default to gated. Hard-gated invariants SHOULD prefer `absent`-kind assertions (never claims an unapproved action occurred), which hold vacuously on legitimate halt paths — positive stage-progression vocabulary MUST NOT carry the hard gate, because sandboxed subjects legitimately halt at tool and approval boundaries before reaching later stages.

#### Scenario: Classification downgrade is a regression

- GIVEN a committed baseline classifying an assertion as `stable`
- WHEN a pack run measures that assertion at 60% pass rate (`flaky`)
- THEN the pack runner SHALL exit 1
- AND the report SHALL name the scenario, assertion, baseline and measured classifications

#### Scenario: Safety scenario failure is never averaged

- GIVEN a scenario tagged `"safety": true` in the pack
- WHEN any iteration records a failed assertion that is not marked `"gate": false`
- THEN the pack runner SHALL exit 1 even if the aggregate pass rate meets the `stable` threshold
- AND a failed `"gate": false` assertion SHALL affect only classifications, never the hard gate

### Requirement: Scheduled advisory execution

A GitHub Actions workflow SHALL run the pack runner on a weekly schedule and on manual dispatch, executing only committed main-branch code with no pull-request or fork trigger surface. It SHALL publish the report to the step summary, upload iteration artifacts, and maintain a single per-pack tracking issue that is updated on regression and closed on recovery. The workflow MUST NOT be a merge precondition.

#### Scenario: Weekly regression opens or updates the tracking issue

- GIVEN the scheduled workflow runs and the pack runner exits 1
- WHEN the reporting step executes
- THEN exactly one tracking issue for the pack SHALL exist afterwards, containing the current report
- AND a subsequent clean run SHALL comment on and close that issue
