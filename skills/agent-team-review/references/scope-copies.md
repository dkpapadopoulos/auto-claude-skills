# agent-team-review — the paired do-not-flag copies

Read before editing the do-not-flag table in SKILL.md §3 or any lens's `## Scope` block in `references/reviewer-prompts.md`. Moved verbatim from SKILL.md.

**PAIRED — this table is the LEAD's copy; the reviewer's copy ships in the spawn
template.** A reviewer sees only its own prompt, so a scope rule stated only here
constrains nobody: it was claimed as reviewer scope and delivered to no reviewer
until #245. The same two categories are carried verbatim in every lens prompt's
`## Scope` block. `tests/test-reviewer-dispatch-brief.sh` asserts each lens carries
them, that the four copies are byte-identical, and that the category SET here and
in the prompts is the same; `tests/test-adversarial-governance.sh` asserts the
delivered copy still stops at two. Editing one copy fails the gate — fix that by
editing the other, never by deleting the assertion.
