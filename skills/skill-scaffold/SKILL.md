---
name: skill-scaffold
description: Emit repo-native seed files (SKILL.md skeleton, routing entry, test snippets) when creating new skills, commands, or plugins
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

Note: Also needs a matching entry in `config/fallback-registry.json` using compact single-line trigger format.

The routing entry `description` field follows the same description rule as the frontmatter: purpose and when-to-use, never workflow steps.

## Step 4: Emit Test Snippets

**Routing test** (for `tests/test-routing.sh`):

```bash
test_<skill_name>_triggers() {
    echo "-- test: <skill-name> triggers on <trigger phrase> --"
    setup_test_env
    install_registry_with_<appropriate_helper>

    local output
    output="$(run_hook "<sample prompt>")"
    local context
    context="$(extract_context "${output}")"

    assert_contains "<skill-name> fires" "<skill-name>" "${context}"

    teardown_test_env
}
```

**Content/behavior assertion:**

```bash
test_<skill_name>_content_contract() {
    echo "-- test: <skill-name> SKILL.md has required sections --"
    local skill_file="${PROJECT_ROOT}/skills/<skill-name>/SKILL.md"

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
