# Observability for context-economy

Reading guide for the data sources that inform context-economy decisions, and
the probation contract that gates Task D's default-on flip.

## What's measurable today

Three layers, increasing in fidelity:

### 1. `/usage` (built-in, paid plans)

Run `/usage` inside any Claude Code session for per-MCP, per-subagent, per-skill,
per-plugin attribution of cost and activity for the current session. Built into
Claude Code 2.x; no install required.

What to look at:

- **Per-MCP token cost.** Which servers are eating context before you've typed a
  prompt? Disable per-session with `/mcp` or persistently via `disabledMcpServers`
  in `~/.claude.json`.
- **Per-subagent breakdown.** Subagent-heavy workflows can consume ~7× the
  tokens of a single-thread session (Anthropic guidance). If subagents dominate,
  consider whether `CLAUDE_CODE_SUBAGENT_MODEL=haiku` (Task D) materially
  changes the cost without degrading quality on those specific agents.
- **Cache hits.** Reads at ~10% of full input price. Mid-session model swaps,
  MCP toggles, and CLAUDE.md edits all invalidate the prefix.

### 2. `ccusage` (third-party CLI)

`ccusage` parses `~/.claude/projects/*.jsonl` (Claude Code's local transcript
store) into daily / weekly / monthly tables. Install:

```bash
npm install -g ccusage
ccusage daily
ccusage monthly
```

Useful for cross-session trends. Does NOT capture content (privacy-preserving)
— only token / cost / model metadata.

### 3. OpenTelemetry (opt-in via `/setup --observability`)

`/setup --observability` writes the OTEL env block into `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp"
  }
}
```

You supply the collector endpoint (`OTEL_EXPORTER_OTLP_ENDPOINT`). The preset
deliberately does NOT default an endpoint — pick a destination (Datadog,
Grafana, Splunk, local Jaeger) and configure it.

Coverage (per Anthropic docs): `input_tokens`, `output_tokens`, cache read/write,
estimated cost, model name, effort level, query source, MCP/server/tool
attribution, tool result size, duration, failures. Content is NOT recorded by
default (opt-in via separate flags).

**What OTEL cannot prove:** semantic task quality. A capped MCP output that
loses the smoking-gun log line will show identical token counts but a worse
investigation outcome. Always pair telemetry with a human pass/fail check on
real workloads.

## Probation contract for Task D (model routing)

`/setup --model-routing` is **opt-in and default-OFF**. The default-on flip is
gated on the following criteria:

1. **At least two weeks of OTEL telemetry** (Task B enabled and shipping data)
   showing no review-quality regressions.
2. **A pass/fail check on a known-regression fixture** — run a code-review
   subagent against a PR with a deliberate, subtle bug. Haiku-tier review MUST
   catch the bug at the same rate as the baseline (default-model) review.
3. **No user reports of degraded behavior** from anyone who opted in early.

If all three pass, the default flips in the next release. The change MUST be
documented in `CHANGELOG.md` under that release with the explicit telemetry
summary (sample size, model-mix breakdown, fixture pass rate).

If any of the three fail, the preset stays opt-in indefinitely. The cost
savings are real but not worth a silent reviewer-quality regression.

### Running criterion 2 (the known-regression fixture)

The fixture lives at `tests/fixtures/model-routing/`: a self-contained reviewer
prompt (`reviewer-guidance.md`) plus a review pack (`review-pack.json`) whose
scenario embeds one deliberate, subtle bug — a `local var=$(cmd)` that masks the
command's exit code, so a `$?` check tests `local` (always 0) instead. The bug
is **not** documented in `CLAUDE.md`, so the test measures model reasoning, not
recall of a known gotcha.

The probation is comparative. Run the same scenario under Haiku and under the
baseline model with `--variance N` and compare the per-assertion pass-rate
tables the runner emits:

```bash
# Haiku-tier review
BEHAVIORAL_EVALS=1 SKILL_PATH=tests/fixtures/model-routing/reviewer-guidance.md \
  tests/run-behavioral-evals.sh \
  --scenario local-masks-exit-code \
  --pack tests/fixtures/model-routing/review-pack.json \
  --model haiku --variance 10 \
  --variance-report docs/plans/model-routing-haiku.md

# Baseline review (e.g. sonnet) — same command, --model sonnet
BEHAVIORAL_EVALS=1 SKILL_PATH=tests/fixtures/model-routing/reviewer-guidance.md \
  tests/run-behavioral-evals.sh \
  --scenario local-masks-exit-code \
  --pack tests/fixtures/model-routing/review-pack.json \
  --model sonnet --variance 10 \
  --variance-report docs/plans/model-routing-sonnet.md
```

**On `--bare` and the inner agent's environment:** the inner `claude -p`
inherits this plugin's own skill-activation hooks, so its review is prefixed
with the skill banner ("N skills active... Phase: ..."). The `--bare` flag
strips that, but it also disables OAuth credential loading — under a normal
OAuth login it fails with "Not logged in" and only works when
`ANTHROPIC_API_KEY` (or `apiKeyHelper` via `--settings`) is set. So: use
`--bare` only in an API-key/sandbox context; under OAuth, **omit it**. Omitting
it is measurement-safe here because the catch-detector keys on masking-insight
words the banner never contains — verified, the banner does not move the
catch/miss verdict.

**Pass criterion:** Haiku's catch-rate classification must be `stable` (≥90%)
AND not materially below the baseline's. If Haiku lands `flaky`/`broken` while
the baseline is `stable`, criterion 2 fails and reviewers stay on the strong
model. Note the `--model` flag pins the *inner* `claude -p` model; it is
independent of `CLAUDE_CODE_SUBAGENT_MODEL`.

The catch-detector is a keyword-presence regex (the single `text` assertion in
`review-pack.json`) that fires on the masking insight — that the checked exit
status belongs to `local`/the assignment, not jq. It is **not** a proximity
regex: real model output is markdown, and `**bold**`/`` `code` `` inflate token
distances enough to break `.{0,N}` windows (learned the hard way — an early
proximity regex scored a correct Haiku review as a miss). The discriminator is
pinned against an adversarial sample in `tests/test-model-routing-regex.sh`;
update that test in lockstep if you touch the assertion.

Caveat: the fixture isolates model capability with a generic reviewer prompt,
not the exact `agent-team-review` reviewer instructions. It measures whether a
competent reviewer prompt on Haiku catches the bug — not end-to-end fidelity of
any one shipping skill's dispatch.

### Results to date (2026-05-29)

The pack carries five scenarios spanning obvious → very-subtle, all undocumented
in `CLAUDE.md` (reasoning, not recall). At variance ×5, Haiku 4.5 and Sonnet 4.6
**both scored 5/5 `stable` on every scenario** (unquoted-test, local-masks,
pipeline-subshell, octal-arithmetic, duplicate-trap).

Read this two ways. (1) On single, well-defined, localized bugs, Haiku matches
the baseline across the whole subtlety range — supports the dollar-cost case for
discrete-bug review. (2) **The subtlety ladder is non-discriminating: both models
saturate at 100%, so it cannot separate reviewers.** The dimension that has
separated models (an in-session race where the strong model alone flagged an
*unplanted, systemic* fail-open issue, 3/3 vs 0/3) is emergent/systemic insight,
which these single-bug scenarios do not probe. A real criterion-2 gate needs a
*discriminating* scenario — multi-bug interaction, an emergent property, or a
"what's missing / what's the systemic risk" prompt — not more localized bugs.
This expansion confirms breadth of competence; it does not establish general
review parity.

A code review of the expansion flagged that the `duplicate-trap-exit` and
`pipeline-subshell-lost` detectors were loose enough to score a *description-only*
or *collateral* observation as a catch (e.g. "there are two trap statements" or a
missing-path "the sum is lost"). Both detectors were hardened to require the
replacement/subshell insight, the calibration test gained those adversarial weak
samples, and the two scenarios were **re-measured** — both models held 5/5
`stable`, confirming the result was genuine, not a loose-regex artifact.

A sixth `systemic` scenario (`systemic-gate-fail-open`) was then added to probe
emergent reasoning: a deploy gate that logs unhealthy dependencies but has no
`return 1` anywhere, so it unconditionally returns 0 and can never block. Both
models again scored **5/5 `stable`**, and a verbatim Haiku review confirms the
result is genuine ("always returns 0… never blocks the deploy… the opposite of
the stated intent"), not a detector artifact. A subsequent code review flagged
that the systemic detector's bare `only logs`/`just logs`/`does not block`
branches could match a *neutral* control-flow restatement ("it just logs and
returns 0 as designed") without the reviewer grasping the defect; those branches
were removed, adversarial neutral-description samples added to the calibration
test, and both models **re-measured at 5/5** — confirming the catch was earned.

**Hypothesis (later disconfirmed) — what might discriminate.** A *primary*
systemic bug does NOT separate the models. An earlier in-session race had the
strong model alone flag a systemic issue (3/3 vs 0/3), which suggested the axis
was **depth beyond the first finding** — surfacing a non-obvious, *secondary*
issue when easy findings are present. To test that, a 7th scenario
(`layered-depth-promote-fail-open`) was built: obvious unquoted-var decoys
layered OVER a deep fail-open (a promotion gate that greps the smoke log for
`FAIL`, so a crashed/empty log promotes a broken build). The detector scores
ONLY the deep catch — a review that flags just the decoys is a MISS.

**Result: both models 5/5 `stable`, and genuinely so.** A verbatim Haiku review
surfaced the deep fail-open ("if `run_smoke_tests` crashes… doesn't write FAIL…
proceeds to deploy anyway") AND the decoys. So the depth-beyond-first-finding
hypothesis is **disconfirmed**: Haiku 4.5 has that depth too, and the earlier
race's 0/3 did not replicate under a clean reviewer prompt with a dedicated
scenario.

(Validity: a 4th code review caught that the deep detector's bare `crash` /
`empty log` / `errors out` branches matched a decoy-only or speculative review
without the fail-open insight, and that an unchecked `deploy_to_prod` exit was a
confounding *second* deep bug. The detector was hardened to tie every symptom to
being-treated-as-success, the snippet reduced to a single deep bug, adversarial
decoy-only samples added to the calibration test, and both models **re-measured
at 5/5** — so the catch was earned, not a loose-regex artifact. This was the
fourth detector on this fixture whose initial bare-keyword branches a review had
to tighten: the durable rule is that a free-text catch-detector must require the
*insight* — symptom tied to wrong conclusion — never a bare symptom token.)

**Bottom line for criterion 2.** Across all seven scenarios — obvious,
very-subtle, systemic, and layered-depth — Haiku 4.5 and Sonnet 4.6 are
**empirically indistinguishable** (every cell 5/5 `stable`, each spot-checked
genuine). For this repo's Bash-review profile, the fixture gate of criterion 2
is met. Engineering still-harder scenarios to manufacture a gap would be
p-hacking; the disciplined read is that reviewer parity holds here. (Criteria 1
— ≥2 weeks OTEL telemetry — and 3 — no degraded-behavior reports — remain the
open gates before any default flip.)

## What `MAX_MCP_OUTPUT_TOKENS=10000` costs you

Anthropic's default is 25000 with a warning floor at 10000. Setting the floor
shrinks per-call MCP payloads by ~60%. For most workflows this is invisible —
search results, doc fetches, and small API responses fit well under 10k tokens.

Where it bites:

- **Large log fetches.** `gcp-observability.list_log_entries` over a wide time
  window can return >10k tokens. The cap forces a tighter window or pagination.
- **Bulk Confluence page fetches.** A large knowledge-base page can exceed
  10k tokens; the cap forces sectional reads or markdown-summary requests.

The Task 0 race-test (`tests/race-truncation-defaults.sh`) measures this on a
real GCP-log incident-analysis session. Run the race before committing the
default change; abort if the capped run misses the investigation conclusion.

## What `BASH_MAX_OUTPUT_LENGTH=20000` costs you

Excess bash output is saved to a file and the model receives a path + preview
(per Anthropic docs). No information is permanently lost; the in-context slice
shrinks. Most test runners, builds, and log greps fit comfortably under 20k
chars when pre-filtered. If a tool routinely produces >20k chars of essential
output, either pre-filter (`grep | head`) or raise the cap for that session.

## See also

- `openspec/changes/context-economy-defaults/proposal.md` — full rationale.
- `openspec/changes/context-economy-defaults/design.md` — debate panel views.
- `docs/plans/2026-05-28-race-truncation-results.md` — Task 0 result log.
