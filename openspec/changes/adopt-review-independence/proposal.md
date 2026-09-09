# Adopt review-independence discipline from patforna/auto-task + core-skills

## Why

A five-part assessment of `patforna/writing`, `patforna/auto-task` and
`patforna/core-skills` proposed seven adoption tranches. A four-voice design
debate (architect / critic / pragmatist + a cross-family Codex run) cut them to
two paragraphs of prose plus two hygiene fixes. Everything else was rejected on
**measured** grounds, not taste. Full debate, dissents and the measurements in
`docs/plans/2026-09-08-writing-repo-acs-learnings-design.md`.

The two surviving grafts fill gaps that are verified absent from ACS and that
ACS's own enforcement already assumes:

- **No do-not-flag list.** `grep -i 'do.not.flag|never.flag'` over `skills/`
  returns nothing. The severity floor (`agent-team-review/SKILL.md:97`) filters
  by evidence and design-doc mapping, never by provenance. Because
  `project-verification` and `security-scanner` are separate skills, a reviewer
  restating lint/type/test/SAST output is duplicated **by construction**.
- **No authorship guard.** ACS credits the REVIEW milestone on a Skill return;
  observed dispatch and completion are recorded as advisory evidence only and
  NO gate reads them (#241: "No gate reads the new milestone in this change";
  `grep -c reviewer-returned hooks/openspec-guard.sh` is 0). So a self-review
  reaches SHIP with a green gate, and no owned file states why that is
  unreliable.

## What Changes

**PR 1 — prose grafts into one owned skill (mechanism 1: zero routing/token cost).**
- `skills/agent-team-review/SKILL.md`: a do-not-flag list restricted to
  `pre-existing` and `tool-owned`, and an authorship guard.
- `tests/test-agent-team-review-content.sh` (or the existing content test):
  pin both by grep.

**PR 2 — doc truth and a live tripwire (no `skills|config|hooks` paths).**
- README skill count derived by test, not hand-written (says 18; `skills/` has 23).
- `tests/test-incident-analysis-content.sh:727`: fixed 11,500 ceiling becomes a
  baseline ratchet. **Urgent** — the file is at 11,434 words, 66 words of slack,
  and will otherwise fail an unrelated PR.

## Capabilities

- **Modified:** `adversarial-review` (both grafts)
- **Touched, no spec delta:** `readme` (derived count), `incident-analysis`
  (ratchet — a test-threshold change, no behavioural requirement)

## Impact

`skills/agent-team-review/SKILL.md`, one content test, `README.md`, one
test-threshold change. No hook edits, no config edits, no new skill, no routing
entry, no composition change, no gate armed, no lethal-trifecta leg added.

## Explicitly rejected (each with its measurement)

- **The PLAN/IMPLEMENT/REVIEW hint bundle.** The PR #45 "no measured benefit"
  bar is cited as binding at four sites. The one red-first A/B this repo ran on
  injection wording returned **negative** — on both sonnet and haiku "the
  passive baseline already produces the corrective action"
  (`archive/2026-07-02-correction-ergonomics/design.md`, Decision 6), and the
  team refused to tighten assertions to force baseline-red. Every proposed hint
  is of that class.
- **`core-skills` as a companion plugin.** Unimplementable as specified: `.when`
  is read by no hook (`grep -rn '\.when' hooks/` is empty), and `.plugin`
  resolves through `_plugin_installed`
  (`hooks/session-start-hook.sh:1370-1381`), whose catch-all arm only checks
  `claude-plugins-official/${name}` — so a third-party plugin is **always**
  false. `.plugins[]` also has no version field, so an entry hand-copies an
  upstream surface with no pin, and staleness is invisible to non-installers.
  `adopt-addy-mechanics` rejected this exact shape by name.
- **A `second-opinion` skill, in both proposed forms.** `agent-team-review:192`
  is not decorative — it has a recorded successful invocation
  (`archive/2026-06-11-adopt-doubt-discipline/design.md:36`: offered, provider
  hit a session limit, "recorded in the plan rather than silently skipped").
  Its narrowness is a confidentiality control, and widening it scores the full
  lethal trifecta (private_data + untrusted_input + outbound_action), which
  ACS's own REVIEW hint calls a blocking governance finding.
- **A "fail loudly, never substitute" rule.** Refuted three ways: the source
  contradicts itself (`core-skills/skills/review-loop/SKILL.md:90` — "Never
  fail because an external model is down"); the paper it rests on is
  model-agnostic (the gain is context separation); and it would be ACS's first
  surface that stops rather than announces, against #198.
- **The CLAUDE.md 19-bullet migration.** Headline token figure withdrawn as
  never measured; destination capacity-bound (index at 3,810 B of an 8,192 B
  cap that refuses whole, not truncates); moving mandatory instructions to a
  surface framed "untrusted notes, verify before acting" is a demotion, not a
  relocation.
- **The `software-design` red-flags checklist as an artifact.** Vendored
  upstream prose with no update path. Keep only the ACS-specific mapping
  (Information Leakage ≡ #166, Repetition ≡ the 6-copy token incantation),
  written in ACS's words.
