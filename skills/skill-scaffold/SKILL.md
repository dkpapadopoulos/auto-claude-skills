---
name: skill-scaffold
description: Use when creating new skills, commands, or plugins — emits repo-native seed files (SKILL.md skeleton, routing entry, test snippets)
---

# Skill Scaffold

Emit seed files for new additions to auto-claude-skills. Ensures agents follow existing patterns from the first file.

## When to Use

During DESIGN phase when creating new skills, commands, plugins, hooks, or modules. Co-selects with writing-skills.

## Step 1: Identify Addition Type

Ask: What are we creating?

| Type | Skeleton | Notes |
|------|----------|-------|
| Domain skill | SKILL.md + routing entry + routing test + content assertion | Default. Most new additions are domain skills. |
| Workflow skill | SKILL.md + routing entry + routing test + composition test | Include `precedes`/`requires` fields. |
| Edge-overlay process skill | SKILL.md + routing entry + routing test + content assertion | **Restricted to DISCOVER and LEARN phases only.** If the user requests a process skill for a superpowers-owned phase (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG), emit a warning: "This phase's process driver is owned by superpowers. Consider a domain skill instead." |
| Hook | Script + config entry + syntax test | Bash 3.2 compatible. |
| Command | Command markdown + setup registration | Follow existing `commands/` pattern. |

## Step 2: Emit SKILL.md Skeleton

Generate based on type. Include frontmatter, tiered detection where applicable, and output contract section.

**Description rule:** the frontmatter `description` states what the skill is for and when to use it. Do not summarize the workflow steps — an agent may follow the summary instead of reading the full skill.

**Domain skill SKILL.md skeleton:**

```
---
name: <skill-name>
description: <one-line description>
---

# <Skill Name>

<One paragraph purpose statement.>

## When to Use

<Phase and activation context.>

## Step 1: Detect Available Tools

<Tiered detection pattern if the skill depends on external tools.>

## Step 2: <Primary Action>

<Core behavior.>

## Output Contract

<What the skill produces -- artifacts, reports, structured data.>
```

### Optional anatomy sections (discipline / readiness-claim skills)

Add these ONLY where they earn their place. A skill that enforces a discipline, is commonly skipped or shortcut under pressure, or makes a completion/readiness claim should carry the matching section. **Keep a section only if it earns its place -- delete the rest. Filler anatomy on tool/domain skills is the anti-goal.**

| Section | Keep when | Shape |
|---------|-----------|-------|
| `## Rationalizations` | the skill is commonly skipped or shortcut under pressure | table of excuse -> reality |
| `## Red Flags` | the skill enforces a discipline with known failure modes | bulleted anti-patterns / "thought -> STOP" list |
| `## Verification` | the skill makes a completion or readiness claim | "Before claiming `<X>`, confirm: ..." evidence-before-assertions checklist |

Template (paste, then keep-or-delete per the table above):

```
## Rationalizations

| Excuse | Reality |
|--------|---------|
| "<excuse the agent makes to skip this>" | "<why that's wrong>" |

## Red Flags

- **<anti-pattern>** -- <why it means stop>

## Verification

Before claiming <the skill's specific completion claim>, confirm -- with evidence, not inference:

- <observable check tied to the claim>
```

The qualifier after `confirm --` is the canonical default; adapt it to the claim's failure mode (e.g. `do not infer` for state checks, `from observed output` for execution checks).

## Step 3: Emit Routing Entry Snippet

Generate a JSON snippet for `config/default-triggers.json`:

```json
{
  "name": "<skill-name>",
  "role": "domain",
  "phase": "<PHASE>",
  "triggers": [
    "<regex-pattern>"
  ],
  "keywords": ["<keyword1>", "<keyword2>"],
  "trigger_mode": "regex",
  "priority": 15,
  "precedes": [],
  "requires": [],
  "description": "<one-line description>",
  "invoke": "Skill(auto-claude-skills:<skill-name>)"
}
```

The routing entry MUST be added to **both** `config/default-triggers.json` and `config/fallback-registry.json`.

The routing entry `description` field follows the same description rule as the frontmatter: purpose and when-to-use, never workflow steps.

## Step 4: Emit Test Snippets

**Routing fixture** (`tests/fixtures/routing/<skill-name>.txt`) — the deterministic
done-gate. REQUIRED for every owned skill that has a trigger regex:

```
# <skill-name> routing fixtures
MATCH: <realistic prompt the trigger regex matches>
MATCH: <a second, differently-phrased positive>
NO_MATCH: <a decoy borrowed from another skill's fixture — must NOT match>
```

Borrow the NO_MATCH decoy from an existing `tests/fixtures/routing/*.txt` so an
over-broad regex fails the gate. `tests/test-fixture-coverage.sh` fails the build
if this file is missing or lacks a MATCH or NO_MATCH line.

**Trigger-accuracy eval** (`skills/<skill-name>/evals/evals.json`) — optional but
recommended; the held-out LLM trigger eval (`skill-creator` / `skill-eval.yml`)
reads it. See `docs/eval-pack-schema.md`.

**Content/behavior assertion** (for a `tests/test-<skill>-content.sh`): keep the
SKILL.md non-empty + frontmatter `name:` check.

```bash
test_<skill_name>_content_contract() {
    echo "-- test: <skill-name> SKILL.md has required sections --"
    local skill_file="${PROJECT_ROOT}/skills/<skill-name>/SKILL.md"

    # Bash 3.2: declare `local` and assign on SEPARATE lines. `local x=$(...)`
    # swallows the command's exit code (local always returns 0), masking failures.
    local content
    content="$(cat "${skill_file}" 2>/dev/null || echo "")"
    assert_not_empty "<skill-name> SKILL.md exists and is non-empty" "${content}"
    assert_contains "<skill-name> has frontmatter name field" "name:" "${content}"
}
```

## Constraints

- Produces snippets, not complete files. The user or agent integrates them.
- Does not auto-register skills -- registration is a deliberate step during REVIEW.
- Adapts skeleton to skill type (domain, workflow, edge-overlay process).
- All output follows Bash 3.2 and repo JSON conventions.
