---
description: Launch a systematic incident investigation
argument-hint: "Service name and symptoms (e.g., 'user-service 500s in hb-prod')"
---

Launch the incident-analysis skill for a systematic, evidence-based investigation of a
production incident.

## What Happens

1. The skill detects available tools (MCP, gcloud CLI, or guidance-only)
2. Establishes scope: service, environment, time window from your input
3. Runs inventory and impact quantification (MITIGATE stage)
4. Classifies the incident against playbooks (CLASSIFY stage)
5. Investigates with targeted queries (INVESTIGATE stage)
6. If remediation is needed, presents playbook with HITL gate (EXECUTE stage)
7. Validates post-mitigation (VALIDATE stage)
8. Generates structured postmortem (POSTMORTEM stage)

## Usage

**With arguments:**
The `$ARGUMENTS` are passed as initial context. Include the service name, environment, and
symptoms.

**Without arguments:**
The skill will ask for incident details interactively.

## Steps

1. Load the `incident-analysis` skill using the Skill tool.
2. **Preflight:** Before entering Stage 1, run the observability preflight:
   ```bash
   bash '<PLUGIN_ROOT>/scripts/obs-preflight.sh'
   ```
   Report any issues from the `summary` field.
3. **Determine mode:** If the prompt contains triage keywords ("quick triage", "live triage",
   "what's happening right now"), use live-triage mode. Otherwise use full investigation.
4. Begin at Stage 1 — MITIGATE. Pre-populate scope from `$ARGUMENTS`:
   - Extract service name, environment (hb-prod, dg-prod, etc.), and symptoms
   - Convert any local times to UTC
   - Pass extracted context as MITIGATE Step 2 (Establish Scope) inputs
5. **Access gate (Step 1b):** In full mode, wait for fix-or-proceed on auth issues.
   In live-triage mode, snapshot access state and proceed immediately — note gaps.
6. Follow the investigation pipeline as defined in the skill for the selected mode.

## Investigation Modes

**Full investigation (default):** All stages run in order with full inventory, impact
quantification, and aggregate fingerprinting before classification.

**Live triage (opt-in):** For active, ongoing incidents where time-to-first-hypothesis matters.
Activated by including "quick triage", "live triage", or "what's happening right now" in
the prompt. Uses non-blocking access check, light inventory (replica count only), and defers
impact quantification until after the first hypothesis.

All safety guarantees (HITL gate, fingerprint recheck, completeness gate) remain active
in both modes.

## Important

- All investigation is **read-only** by default
- Remediation actions require **explicit user approval** (HITL gate)
- Must not bypass MITIGATE steps in full investigation; live-triage defers deep inventory and impact until after first hypothesis
