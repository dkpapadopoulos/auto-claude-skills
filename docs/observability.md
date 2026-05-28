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
