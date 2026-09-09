# Codex adversarial review (cross-family, read-only repo access)

Model: codex-cli 0.146.0. Run 2026-09-09 against the 7 consolidated
recommendations in Part 3. Prompt: `2026-09-08-codex-cold-assessment-prompt.md`
lineage, re-cut for the adversarial contract (>=2 rejections, >=1 hidden
cost, >=1 missed opportunity required). Verbatim output below.

## Measurements I re-ran

| claim | my result | verdict |
|---|---:|---|
| `CLAUDE.md` ≈13.9k words | `wc -w CLAUDE.md` → **14,168** | Wrong/currently stale |
| Gotchas: 30 bullets | `awk 'NR>=54&&NR<86&&/^- /{n++}END{print n}' CLAUDE.md` → **30** | Correct ([CLAUDE.md:52](/Users/damian/IdeaProjects/auto-claude-skills/CLAUDE.md:52)) |
| 19 test-backed bullets / 12,881 words; 11 others / 405 words | Classifying those 30 lines by `tests/test-*.sh`, then subtracting each bullet marker from `NF` → **19 / 12,881; 11 / 405** | Correct |
| Largest gotcha: 3,284 words | Same command → **3,284**, line 71 | Correct ([CLAUDE.md:71](/Users/damian/IdeaProjects/auto-claude-skills/CLAUDE.md:71)) |
| Saving ≈17k tokens/session | No tokenizer or session-context measurement supplied; relocation would replace instructions with index metadata | Unsupported |
| README says 18; `skills/` has 23 | `find skills -mindepth 1 -maxdepth 1 -type d \| wc -l` → **23**; README says **18** | Correct ([README.md:117](/Users/damian/IdeaProjects/auto-claude-skills/README.md:117)) |
| Superpowers drives 6/8 phases | `jq -r '.phase_compositions[].driver' …` → six Superpowers names; DISCOVER and LEARN are ACS skills | Correct ([default-triggers.json:1277](/Users/damian/IdeaProjects/auto-claude-skills/config/default-triggers.json:1277), [default-triggers.json:1355](/Users/damian/IdeaProjects/auto-claude-skills/config/default-triggers.json:1355), [default-triggers.json:1492](/Users/damian/IdeaProjects/auto-claude-skills/config/default-triggers.json:1492)) |
| Both push milestones are Superpowers skills | Gate messages require `requesting-code-review` and phase-evidence skills under `superpowers:` | Correct ([openspec-guard.sh:1395](/Users/damian/IdeaProjects/auto-claude-skills/hooks/openspec-guard.sh:1395), [openspec-guard.sh:1666](/Users/damian/IdeaProjects/auto-claude-skills/hooks/openspec-guard.sh:1666)) |
| Incident skill: 11,223 words under 11,500 cap | `wc -w skills/incident-analysis/SKILL.md` → **11,218** | Numeric claim wrong; “ratchet, not constraint” remains correct because only 282 words remain ([test-incident-analysis-content.sh:723](/Users/damian/IdeaProjects/auto-claude-skills/tests/test-incident-analysis-content.sh:723)) |
| Knowledge index is an existing session-start mechanism | `wc -c .claude/knowledge/index.md` → **3,810 bytes**; only link bullets from the index are injected, capped at 8,192 bytes | Correct but materially incomplete ([session-start-hook.sh:1545](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1545), [session-start-hook.sh:1550](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1550), [session-start-hook.sh:1556](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1556)) |

## Would not do

1. **Recommendation #1 — not as proposed.** This is not pure relocation. `CLAUDE.md` is always-loaded project instruction, while session start injects only `index.md` link bullets explicitly framed as untrusted reference data; fact bodies are not loaded ([CLAUDE.md:37](/Users/damian/IdeaProjects/auto-claude-skills/CLAUDE.md:37), [session-start-hook.sh:1554](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1554)). Moving shell-safety and gate invariants therefore removes them from the model’s operative instructions unless it independently follows a link. What to do instead: compress each gotcha into a short normative rule plus regression pointer in `CLAUDE.md`; move only histories, measurements, and incident narratives.

2. **Recommendation #4 — do not gate on a `Verdict` heading.** The current design guard already checks substantive fields and scenario cardinality, yet deliberately fails open ([CLAUDE.md:65](/Users/damian/IdeaProjects/auto-claude-skills/CLAUDE.md:65), [skill-activation-hook.sh:1621](/Users/damian/IdeaProjects/auto-claude-skills/hooks/skill-activation-hook.sh:1621), [skill-activation-hook.sh:1682](/Users/damian/IdeaProjects/auto-claude-skills/hooks/skill-activation-hook.sh:1682)). Heading existence proves neither cold-read independence nor comprehension and is trivially self-satisfied. What to do instead: make the cold reader return structured unanswered questions to the planner; test behavioral detection on seeded ambiguous designs.

3. **Recommendation #2 — reject the scope-manifest broadening and bulk hint injection.** Directory entries already become `dir/*`, and explicit `Allow:` globs already exist ([scope-conformance.sh:49](/Users/damian/IdeaProjects/auto-claude-skills/scripts/scope-conformance.sh:49)). Defaulting new files to broad directory globs weakens the only declared-versus-actual scope check, which is already advisory ([scope-conformance.sh:105](/Users/damian/IdeaProjects/auto-claude-skills/scripts/scope-conformance.sh:105)). What to do instead: preserve exact planned paths; add `Allow:` only for genuinely unpredictable generated outputs. Evaluate new prompt hints separately rather than shipping an inseparable bundle.

## Hidden costs

- Migrating 19 gotchas would enlarge the 3,810-byte knowledge index toward its 8,192-byte refusal threshold; once exceeded, **the entire index is replaced by a prune notice**, not partially retained ([session-start-hook.sh:1548](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1548), [session-start-hook.sh:1558](/Users/damian/IdeaProjects/auto-claude-skills/hooks/session-start-hook.sh:1558)).
- Recommendation #3 duplicates controls already present: causal pairing and positive controls ([agent-team-review/SKILL.md:103](/Users/damian/IdeaProjects/auto-claude-skills/skills/agent-team-review/SKILL.md:103)), anti-rubber-stamping ([agent-team-review/SKILL.md:503](/Users/damian/IdeaProjects/auto-claude-skills/skills/agent-team-review/SKILL.md:503)), and non-clean treatment of unresolved findings ([agent-team-review/SKILL.md:183](/Users/damian/IdeaProjects/auto-claude-skills/skills/agent-team-review/SKILL.md:183)). More overlapping prose increases internal contradiction risk.
- A `degradations[]` field has no enforcement value unless every producer and consumer distinguishes “check failed” from “check absent.” ACS documents that its evidence predicates currently collapse both to exit 1 ([implement-shadow.sh:28](/Users/damian/IdeaProjects/auto-claude-skills/hooks/lib/implement-shadow.sh:28)). **Hypothesis:** an optional array would become decorative reassurance.
- The comparison is category-confused: prompt-only pipelines optimize orchestration prose; ACS also makes outbound-action decisions through hooks and SHA-bound artifacts ([openspec-guard.sh:1440](/Users/damian/IdeaProjects/auto-claude-skills/hooks/openspec-guard.sh:1440)). Copying prompt conventions into enforcement surfaces does not preserve their semantics.

## Missed opportunities

- Generate the README skill inventory from the registry or test exact equality. The current prose says 18 while the filesystem has 23 ([README.md:115](/Users/damian/IdeaProjects/auto-claude-skills/README.md:115)); manual “truth-in-docs” correction will drift again.
- Make optionality machine-readable and surface degraded phase coverage at session start. The README calls integrations optional ([README.md:140](/Users/damian/IdeaProjects/auto-claude-skills/README.md:140)), while IMPLEMENT explicitly requires Superpowers worktree and branch-finishing steps ([default-triggers.json:1402](/Users/damian/IdeaProjects/auto-claude-skills/config/default-triggers.json:1402)).
- Steal the lightweight repos’ real advantage: a small, inspectable phase contract. ACS’s PLAN/IMPLEMENT/REVIEW policy is distributed across compositions, skills, hooks, and `CLAUDE.md` ([default-triggers.json:1355](/Users/damian/IdeaProjects/auto-claude-skills/config/default-triggers.json:1355), [CLAUDE.md:52](/Users/damian/IdeaProjects/auto-claude-skills/CLAUDE.md:52)). Add a generated “phase → required evidence → enforcing consumer → degradation” matrix and test it against configuration.
- Replace the incident word ceiling with a ratchet tied to the committed baseline or a content-budget test by section. The current fixed ceiling merely permits growth back to 11,500 ([test-incident-analysis-content.sh:724](/Users/damian/IdeaProjects/auto-claude-skills/tests/test-incident-analysis-content.sh:724)).

## Ranking I would use

1. **#5, truth-in-docs** — immediate, measurable drift; generate rather than manually patch.
2. **#3, narrow agent-review additions only** — add authorship provenance and a round cap; avoid duplicating existing adjudication rules.
3. **#6, preflight semantics first** — define and consume degradation states before adding fields or knowledge prose.
4. **#1, redesigned as compression** — keep normative rules always loaded; relocate only evidence and history.
5. **#2, split and evaluate** — trial each companion and hint independently; retain exact scope declarations.
6. **#7, defer** — hand-labelling before automation is sound, but lower payoff.
7. **#4, drop** — structural heading enforcement is a gameable proxy for comprehension.
