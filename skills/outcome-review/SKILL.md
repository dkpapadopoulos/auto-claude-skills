---
name: outcome-review
description: Use when reviewing a shipped feature's real-world outcome in the LEARN phase — checking adoption, error, or experiment metrics after release, validating ship-time hypotheses, or deciding follow-up work — querying PostHog and creating gated follow-up Jira work
---

# Outcome Review

Query analytics for a shipped feature, synthesize an outcome report, and optionally create follow-up Jira work. Entered independently after shipping — days or weeks later.

## Step 1: Detect Available Tools

Check which MCP tools are available:

**Tier 1 — PostHog MCP:**
If you have access to `query-run`, `get-experiment`, `list-experiments`, `get-feature-flag`, or `create-annotation` as MCP tools, use Tier 1.

**Tier 2 — Manual Metrics:**
If no PostHog MCP tools are available, ask the user to provide metrics directly:
> "I don't have PostHog MCP access. Please share any of the following:
> - Dashboard screenshots or metric summaries
> - Adoption numbers, funnel data, or error rates
> - Experiment results if applicable
> - Any specific concerns about the shipped feature"

## Step 2: Identify the Feature

1. Check for a learn baseline file in `~/.claude/.skill-learn-baselines/`:
   - List files, match by feature name or branch name from the user's prompt
   - If found, use the baseline's `shipped_at`, `ship_method`, `hypotheses`, and `jira_ticket` fields
   - If `ship_method` is `"pull_request"`, verify the PR was actually merged before proceeding (check `pr_url` via `gh pr view`)
2. If no baseline found, ask the user:
   > "Which feature should I review? Please provide the feature name, branch name, or Jira ticket ID."

## Step 3: Gather Metrics

**Tier 1 (PostHog MCP available):**

1. Query adoption metrics via `query-run` with HogQL:
   - Event counts for the feature's key events since `shipped_at`
   - Compare to the period before shipping (same duration)
   - If the baseline has non-null `hypotheses`, use each hypothesis's `metric` field to target specific events/properties instead of generic adoption queries
2. Check experiment results if applicable:
   - `list-experiments` to find experiments linked to the feature
   - `get-experiment` for results, significance, and variant performance
3. Check feature flag status:
   - `get-feature-flag` for rollout percentage and targeting rules
4. Check error rates:
   - `query-run` for error events associated with the feature

**Tier 2 (Manual):**

1. Ask the user to share metrics from their dashboards
   - If the baseline has `hypotheses`, present each hypothesis and its metric to the user: "For H1 ([description]), I need the current value of [metric]. What is it?"
2. Ask about any observed regressions or improvements
3. Synthesize from what the user provides

## Step 4: Synthesize Outcome Report

Present a structured report:

### Outcome Report

**Feature:** [name] | **Shipped:** [date] | **Branch:** [name]

**Adoption:** [metrics summary — event counts, trend direction, comparison to pre-ship baseline]

**Quality:** [error rates, regression indicators]

**Experiments:** [results if applicable — significance, winning variant, effect size]

**Assessment:** One of:
- **Positive** — Metrics improved, no regressions. Close the loop.
- **Regression detected** — [specific metric] degraded by [amount]. Investigate.
- **Inconclusive** — Insufficient data. Revisit in [N] days.
- **Mixed** — [positive metrics] improved but [negative metrics] regressed. Judgment call.

**Hypothesis Validation** (when baseline has non-null `hypotheses`):

| ID | Hypothesis | Metric | Baseline | Target | Actual | Status |
|----|-----------|--------|----------|--------|--------|--------|
| H1 | [description] | [metric] | [baseline] | [target] | [measured value] | [status] |

Status values:
- `Confirmed` — Actual meets or exceeds target
- `Not confirmed` — Actual does not meet target
- `Inconclusive` — Insufficient data, or validation window has not elapsed
- `Partially confirmed` — Directionally correct but below target threshold

When `hypotheses` is null in the baseline (or no baseline found): skip this section entirely. Fall back to the existing generic metrics flow with no behavioral change.

**Recommendations:** Specific next actions based on the assessment.

## Step 5: User Decision Gate

Present the report and ask:
> "Based on this outcome review, would you like me to:
> 1. **Close the loop** — no follow-up needed
> 2. **Create follow-up Jira tickets** — I'll draft tickets for the recommended actions (requires your approval before creation)
> 3. **Investigate further** — dig deeper into a specific metric or regression"

Wait for the user's choice.

## Step 6: Follow-Up Actions

**If "Create follow-up tickets" (and Atlassian Rovo MCP available):**

1. If the baseline lacks `jira_ticket` or the feature's parent ticket is unknown, find it first: call `search(cloudId, "<feature name>")` — the Rovo cross-system search returns the original ticket alongside any linked Confluence docs in one call. Fall back to `searchJiraIssuesUsingJql` only if `search` returns no matches.
2. Draft the ticket(s) — title, description, acceptance criteria, priority.
3. Present each draft to the user for approval.
4. Only after explicit approval: `createJiraIssue` to create the ticket.
5. `addCommentToJiraIssue` on the original ticket with the outcome summary.

**If Atlassian Rovo MCP unavailable:**
> "I don't have Atlassian Rovo MCP access. Here are the recommended follow-up tickets — please create them manually:
> [formatted ticket descriptions]"

## Step 7: Transition

If follow-up work was identified:
> "If follow-up work is needed, invoke Skill(auto-claude-skills:product-discovery) or Skill(superpowers:brainstorming) to begin the next cycle."

If the loop is closed:
> "Outcome review complete. The feature loop is closed."
