## ADDED Requirements

### Requirement: Workflow-Free Skill Descriptions
skill-scaffold MUST direct that skill descriptions (SKILL.md frontmatter and routing entry `description` fields) state what the skill is for and when to use it, and MUST NOT summarize the skill's workflow steps. A description containing process steps risks the agent following the summary instead of reading the full skill.

#### Scenario: Scaffold guidance includes the description rule
- **GIVEN** an agent uses skill-scaffold to seed a new skill
- **WHEN** it reads the SKILL.md skeleton and routing entry steps
- **THEN** both include the rule that descriptions state purpose and when-to-use, never workflow steps
