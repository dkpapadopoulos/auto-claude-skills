# assumption-audit behavioral pack

One scenario: an ungraded discovery ask resting on confidently-asserted, evidence-free
beliefs. Asserts the STRUCTURAL contract the skill adds: (text) an `## Assumption Ledger`
section is emitted (authoritative check: run `scripts/assumption-audit-check.sh` on the
extracted output — that is the deterministic assertion; the in-pack text assertion is its
proxy); (judge) evidence-free beliefs graded expert_judgment/D-family, not A/B; (judge)
criteria/weights confirmed BEFORE option scores.

Run (opt-in): BEHAVIORAL_EVALS=1 SKILL_PATH=skills/product-discovery/SKILL.md \
  tests/run-behavioral-evals.sh --scenario assumption-audit-structural-contract \
  --pack tests/fixtures/assumption-audit/evals/behavioral.json

RED/GREEN evidence (2026-07-10, sonnet, 5 reps/arm): control (pre-audit skill) 0/5 pass
deterministic contract; with-skill 4/5 (5th = h3-Options formatting, correctly flagged).
