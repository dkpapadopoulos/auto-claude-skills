# Cold assessment prompt (for an independent model)

Run this with a model that has NOT seen any prior assessment. Local usage with the
Codex CLI, from a directory containing checkouts of the four repos:

    codex exec --model <strongest> "$(sed -n '/^---PROMPT---$/,$p' docs/plans/2026-09-08-codex-cold-assessment-prompt.md | tail -n +2)" > /tmp/codex-cold-assessment.md

Repos expected as sibling directories (adjust paths in the prompt if different):
`auto-claude-skills/` (this repo, at `main`), `writing/`, `auto-task/`, `core-skills/`
(all from github.com/patforna).

---PROMPT---
You are assessing what an existing Claude Code plugin should learn from three
repositories by another author. Work only from the files on disk. Do not read any
`docs/plans/*learnings*` or `*assessment*` file in the plugin repo, and do not read
its git log: the point is an independent view.

Repositories:
1. `auto-claude-skills/` ("ACS") — the plugin being assessed. Start with its
   `CLAUDE.md`, `README.md`, `skills/*/SKILL.md`, `config/default-triggers.json`
   (the `phase_compositions` section especially), `hooks/hooks.json`, and skim
   `tests/`.
2. `writing/README.md` — an experience report by the author of the other two repos.
3. `auto-task/` — a Claude Code plugin: read every `skills/*/SKILL.md`, `CLAUDE.md`,
   `README.md`, `auto-task.config.defaults.md`, and
   `docs/research/2026-07-03-consolidated-synthesis.md`.
4. `core-skills/` — a companion plugin: read every `skills/*/SKILL.md` and `CLAUDE.md`.

Deliver a written assessment with these sections:

A. In 5–10 bullets, what ACS is and how it enforces its SDLC (mechanisms, not
   marketing). Include any numbers you measured (file sizes, counts) that bear on
   your later recommendations.
B. What the essay and the two plugins do that ACS does not, as a table:
   practice | evidence in source (file, and a quote or number) | verdict
   (adopt / adapt / skip) | where in ACS it would land | why.
C. What ACS does better or already has, so the comparison is not one-sided.
D. Where the two approaches genuinely conflict (not merely differ), and which
   side you would take, with the reason.
E. Your top 5 recommendations, ranked by payoff per unit of effort, each with the
   concrete first change.
F. Anything in either side you believe is wrong or overclaimed, with the evidence.

Rules: answer directly and honestly; do not hedge or soften to be agreeable. If
your honest view differs from what the request seems to expect, give that view.
Cite files for every claim about a repo. Prefer measured facts (word counts,
counts of files, quoted lines) over impressions. Do not pad; a finding with no
evidence should be dropped, not softened.
