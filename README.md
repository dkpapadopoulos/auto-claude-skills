# auto-claude-skills

A [Claude Code](https://code.claude.com) plugin that enables agentic PDLC (agent-assisted product development lifecycle): it helps Claude move from discovery through learning with the right skills, guardrails, and tool context for each phase.

Instead of relying on memory and ad hoc prompting, the plugin gives Claude a stronger operating model across the AI-enabled PDLC. It routes the right skill, surfaces the next step, guards planning/review/verification, and — in spec-driven mode — commits design intent to versioned artifacts so work stays aligned across sessions and teammates.

## Why This Exists

AI accelerates every phase of the lifecycle, but speed exposes three problems:

- **Skill sprawl.** Dozens of installed skills, and remembering which to invoke is the user's job. Useful skills go unused.
- **Skipped discipline.** Review, failing tests, ship verification, and as-built docs are easy to skip when the model feels confident. Small features ship without review; completion claims go unverified.
- **Lost intent.** Design decisions live in chat transcripts, not committed specs. When work resumes in a later session or by a teammate, the *why* is gone and AI-assisted work drifts from intent.

The plugin addresses these by routing skills on intent, gating the skipped transitions, and committing design intent to versioned specs when spec-driven mode is on.

## What It Does

The plugin turns a loose collection of skills, hooks, and integrations into a phase-aware delivery system.

- **Prompt routing by intent.** Each prompt is scored against trigger patterns and matched to relevant skills. Prompts that match nothing produce no output — no noise on non-development work.

- **Phase-aware PDLC orchestration.** The plugin infers a likely phase and composes the relevant skills, sequences, and hints across the delivery lifecycle:

  | Phase | Baseline path | Optional enhancers |
  |-------|---------------|-------------------|
  | DISCOVER | Pulls Jira/Confluence context, synthesizes a discovery brief before design | Context-stack lookups for prior decisions and specs |
  | DESIGN | Activates brainstorming, explores requirements before coding | `design-debate`, `feature-dev`, `frontend-design` when installed and appropriate |
  | PLAN | Structures implementation into discrete tasks with dependency ordering | Context lookups for APIs, blast radius, and past decisions |
  | IMPLEMENT | Drives the execution-plan/TDD workflow; halts if implementation is written before a failing test | `agent-team-execution` for independent tasks, security guidance when installed |
  | REVIEW | Routes into `requesting-code-review` plus security scanning | `agent-team-review`, PR toolkit specialists, runtime validation, and drift checks when applicable |
  | SHIP | Routes through verification, `openspec-ship`, and branch completion | Commit/PR automation and memory consolidation when installed |
  | LEARN | Routes to `outcome-review` for metrics and follow-up work | PostHog and Jira follow-through when installed |
  | DEBUG | Overrides the current phase with structured debugging or incident investigation | `incident-analysis`, `alert-hygiene`, and observability context |

- **Guardrails that support agentic work.** Phase-specific red flags, required sequences, and selective hard gates for high-risk cases like unverified pushes — most enforcement is in-session guidance, not blocking.

- **Optional enrichment from companion tools.** When integrations like Jira, GitHub, Context7, Serena, or GCP Observability are installed, the routing engine injects phase-appropriate context to use them.

- **Versioned intent, not ephemeral chat.** In spec-driven mode, design proposals and as-built specs live in `openspec/changes/`. Hypothesis artifacts, plan files, and team checkpoints are saved to disk so later skills, next sessions, and teammates pick up from the same intent.

## Example Prompts

**"design a secure frontend component"** → DESIGN phase. Activates brainstorming to explore requirements before coding. When `design-debate` is installed and the prompt warrants multi-agent exploration, it can also enter structured debate; `frontend-design` adds UI-specific patterns when installed. Companion tools query library docs for relevant API constraints.

**"debug this login bug"** → DEBUG phase. Activates systematic-debugging (structured root-cause analysis). TDD is injected as a mandatory parallel — reproduce with a failing test before fixing. If GCP Observability is installed, context hints toward runtime logs.

**"investigate this 502 spike"** → DEBUG phase. Activates incident-analysis, which inventories available infrastructure, classifies the failure against 7 bundled playbooks (bad-release, dependency failure, infra failure, node exhaustion, and others), runs a structured investigation with completeness gates, and generates a canonical postmortem with impact quantification.

**"our alerts keep flapping"** → DEBUG phase. Activates alert-hygiene to pull GCP alert policies and incident history, cluster flapping patterns, and produce a confidence-grouped report with prescriptive next actions.

**"ship this feature"** → SHIP phase. Activates a sequence starting with verification-before-completion (evidence before assertions), then openspec-ship (as-built documentation), through to finishing-a-development-branch (merge/PR/cleanup options).

## End-to-End Example

One feature flowing through all seven phases, showing what the plugin injects at each step:

1. **DISCOVER** — *"pull Jira ticket ABC-123 and draft a discovery brief"*
   `product-discovery` activates. Pulls the ticket, synthesizes the problem, and records a hypothesis artifact to reconcile later.

2. **DESIGN** — *"let's design the approach"*
   `brainstorming` runs clarifying questions, captures scope and out-of-scope, and writes `docs/plans/YYYY-MM-DD-<slug>-design.md` with acceptance scenarios before planning begins.

3. **PLAN** — *"break this into tasks"*
   `writing-plans` structures the work; the plan requires user confirmation before execution.

4. **IMPLEMENT** — *"start on task 1"*
   Execution-plan workflow runs. TDD is injected as a parallel — writing implementation before a failing test triggers a halt.

5. **REVIEW** — *"review this before I push"*
   `requesting-code-review` dispatches the code-reviewer subagent with the diff range and plan reference. `security-scanner` runs deterministic checks. For changes touching 3+ files or crossing module boundaries, `agent-team-review` adds parallel specialist reviewers.

6. **SHIP** — *"ship it"*
   `verification-before-completion` blocks ship claims without runner output. `openspec-ship` generates as-built docs that reconcile the DISCOVER hypothesis. `finishing-a-development-branch` presents merge/PR/keep/discard options.

7. **LEARN** — *"check adoption after a week"*
   `outcome-review` queries PostHog/Jira, reconciles actual outcome against the DISCOVER hypothesis, and files follow-up work.

Artifacts from earlier phases stay readable throughout — the plan referenced in REVIEW is the file written in PLAN; the hypothesis reconciled in LEARN is the one recorded in DISCOVER.

## How It Works

1. **SessionStart** builds a cached skill registry by merging default triggers, skills discovered from installed plugins, and any user overrides from `~/.claude/skill-config.json`. Also recovers state from interrupted sessions after compaction.
2. **UserPromptSubmit** scores the prompt against trigger patterns — word-boundary matches score higher than substrings, and skill priority, name similarity, and keyword hits all contribute. The engine selects at most 1 process skill, 2 domain skills, and 1 workflow skill.
3. **Phase composition** layers in requirements appropriate to the detected phase: mandatory TDD during implementation, red-flag halts for unverified completion claims, multi-step sequencing during ship.
4. **Guard hooks** run on other lifecycle events — including OpenSpec compliance checks before commits, Serena nudges when Grep could use symbol navigation, context preservation before compaction, session state recovery after compaction, agent checkpoint tracking, and learning consolidation at session end.

## Install

**Prerequisites:**
- [Claude Code](https://code.claude.com) CLI
- `jq` — `brew install jq` (macOS) or `apt install jq` (Linux)

**Minimal install:**

```
/plugin marketplace add damianpapadopoulos/auto-claude-skills-marketplace
/plugin install auto-claude-skills@acsm
```

**Full experience:**

```
/setup
```

`/setup` walks you through installing companion plugins, skills, and MCP integrations. After setup, each session start shows what's active:

```
SessionStart: 28 skills active (12 of 12 plugins). Setup complete
```

The plugin works without every companion integration — it discovers what's installed and routes accordingly. More tools installed means richer context at each phase.

## Bundled Skills

This plugin ships 18 skills that phase composition selects automatically. Each is registered in `config/default-triggers.json` and discoverable at session start. Invoke one explicitly when the routing hasn't picked it up yet.

| Phase | Skill | Purpose |
|-------|-------|---------|
| DISCOVER | [product-discovery](skills/product-discovery/SKILL.md) | Pulls Jira/Confluence context and synthesizes a discovery brief with structured hypothesis fields |
| DESIGN | [design-debate](skills/design-debate/SKILL.md) | Multi-Agent Debate for complex designs — architect + critic + pragmatist with convergence |
| DESIGN | [prototype-lab](skills/prototype-lab/SKILL.md) | Produces 3 thin comparable variants of a proposed design with a mandatory human validation plan |
| DESIGN | [agent-safety-review](skills/agent-safety-review/SKILL.md) | Evaluates autonomous-agent designs for the lethal trifecta (private data + untrusted input + outbound action) |
| DESIGN | [skill-scaffold](skills/skill-scaffold/SKILL.md) | Emits repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills |
| IMPLEMENT | [agent-team-execution](skills/agent-team-execution/SKILL.md) | Executes plans with 3+ independent file-disjoint tasks via parallel specialist agents with shared contracts |
| IMPLEMENT | [batch-scripting](skills/batch-scripting/SKILL.md) | Bulk file operations using `claude -p` with manifest, dry-run, and log-based retry |
| REVIEW | [agent-team-review](skills/agent-team-review/SKILL.md) | Multi-perspective parallel code review (security, quality, spec compliance, adversarial governance) |
| REVIEW | [security-scanner](skills/security-scanner/SKILL.md) | Semgrep SAST + Trivy vulnerability scanning with self-healing fix loop |
| REVIEW | [runtime-validation](skills/runtime-validation/SKILL.md) | Realistic-context validation — browser E2E, API smoke, CLI checks, a11y audits with unified report |
| REVIEW | [implementation-drift-check](skills/implementation-drift-check/SKILL.md) | Spec-drift detection, assumption surfacing, and coverage gap identification against Intent Truth |
| DEBUG | [incident-analysis](skills/incident-analysis/SKILL.md) | Tiered GCP log investigation with trace correlation, completeness gates, and canonical postmortem output |
| DEBUG | [incident-trend-analyzer](skills/incident-trend-analyzer/SKILL.md) | On-demand postmortem trend analysis — recurrence grouping, MTTR/MTTD from canonical postmortem corpus |
| DEBUG | [alert-hygiene](skills/alert-hygiene/SKILL.md) | Clusters flapping alerts and produces a confidence-grouped report with prescriptive next actions |
| SHIP | [openspec-ship](skills/openspec-ship/SKILL.md) | Creates retrospective OpenSpec change, validates, archives, updates changelog |
| SHIP | [deploy-gate](skills/deploy-gate/SKILL.md) | Pre-ship deployment readiness checklist — verifies configuration, documentation, and CI status |
| LEARN | [outcome-review](skills/outcome-review/SKILL.md) | Queries PostHog metrics, synthesizes outcome report with per-hypothesis validation, creates follow-up Jira work (gated) |
| Cross-cutting | [unified-context-stack](skills/unified-context-stack/SKILL.md) | Tiered retrieval across External / Internal / Historical / Intent Truth with graceful degradation |

## Optional Integrations

Installed via `/setup` unless noted. The routing engine discovers these automatically and injects phase-appropriate context when they're present.

**Core workflow plugins** — superpowers (brainstorming, TDD, debugging, planning, code review), frontend-design, claude-md-management, claude-code-setup, pr-review-toolkit.

**MCP and context sources** — Context7 (library documentation), GitHub (PR and issue management), Serena (LSP-based symbol navigation), Forgetful Memory (cross-session architectural knowledge), Context Hub CLI (curated doc annotations).

**Phase enhancers** — commit-commands (structured commit/PR workflows), security-guidance (passive write-time guard), feature-dev (parallel exploration agents), hookify (custom behavior rules), skill-creator (skill benchmarking), cozempic (context protection — checkpoints team state before compaction, prunes sessions to stay within context limits).

**GCP Observability** — When the observability MCP is installed, incident-analysis and alert-hygiene gain direct log/trace/metric queries instead of falling back to gcloud CLI guidance.

**Atlassian Rovo MCP** (formerly Atlassian MCP) — Jira, Confluence, and Compass connect via `/mcp` as a claude.ai managed integration at `https://mcp.atlassian.com/v1/mcp/authv2`. `/setup` includes a walkthrough that detects existing connections, warns on the legacy `/v1/mcp` endpoint (deprecated after 2026-06-30), and offers a copy-paste defaults block. Skills prefer the Rovo cross-system `search` tool for unified Jira+Confluence discovery.

## Configuration

Optional. Create `~/.claude/skill-config.json` to customize routing behavior:

```json
{
  "overrides": {
    "brainstorming": { "triggers": ["+prototype", "-design"] },
    "security-scanner": { "enabled": false }
  },
  "custom_skills": [
    {
      "name": "my-conventions",
      "role": "domain",
      "invoke": "Skill(my-conventions)",
      "triggers": ["review", "refactor"],
      "description": "Team coding standards"
    }
  ]
}
```

Trigger syntax: `"+keyword"` adds, `"-keyword"` removes, `"keyword"` replaces all defaults.

## Multi-User Mode (spec-driven)

For repos with ≥2 active developers, turn on **spec-driven mode**: design intent is committed to `openspec/changes/<feature>/` (visible to teammates via `git pull`) instead of gitignored `docs/plans/`. Every PR is validated by a GitHub Actions gate.

**30-second setup:**

1. **Enable the preset** in `~/.claude/skill-config.json`:
   ```json
   { "preset": "spec-driven" }
   ```

2. **Install the CI gate** — copy two files from this plugin's repo into your target repo:
   - `.github/workflows/openspec-validate.yml`
   - `scripts/validate-active-openspec-changes.sh`

   Or run `/setup` in Claude Code — it will offer to copy them for you.

3. **Commit and push:**
   ```bash
   git add .github/workflows/openspec-validate.yml scripts/validate-active-openspec-changes.sh
   git commit -m "ci: add OpenSpec Validate PR gate"
   ```

4. **Mark the check as Required** in GitHub Settings → Branches → Branch protection rules for `main`. Add `OpenSpec Validate` to the required status checks list.

Full setup guide and rollback steps: [docs/CI.md](docs/CI.md).

**Optional: per-capability review routing.** Copy `.github/CODEOWNERS.template` into your repo as `.github/CODEOWNERS` and replace the `@your-*-team` placeholders. Every PR that touches a capability's spec will auto-request review from that capability's owner.

**What changes:** DESIGN phase writes to `openspec/changes/<feature>/proposal.md` + `design.md` + `specs/<cap>/spec.md` (committed) instead of `docs/plans/*.md` (gitignored). `openspec-ship` validates and syncs the existing change at SHIP time instead of creating from scratch. Task plans (`docs/plans/*-plan.md`) stay local in both modes.

**Without the CI gate installed:** session-start emits a one-line warning nudging you to run `/setup` or copy the workflow files manually.

## Diagnostics

```
/skill-explain "design a secure frontend component"
```

Shows trigger matches, scoring, role-cap filtering, and the context that would be injected.

| Variable | Effect |
|----------|--------|
| `SKILL_EXPLAIN=1` | Routing explanation with raw scores to stderr |
| `SKILL_VERBOSE=1` | Full output regardless of session depth |

## What It Is Not

- **Not IDE autocomplete.** It doesn't suggest code inline — it routes to skills and workflows that guide how you work.
- **Not a ticketing or backlog system.** It can pull context from Jira via MCP, but doesn't manage tickets.
- **Not a monitoring platform.** It investigates incidents and analyzes alert hygiene using your existing GCP infrastructure, but doesn't deploy alerting policies or run monitoring.

It orchestrates Claude Code's in-session workflow and points to external tools where relevant.

## Uninstalling

```
/plugin uninstall auto-claude-skills@acsm
```
