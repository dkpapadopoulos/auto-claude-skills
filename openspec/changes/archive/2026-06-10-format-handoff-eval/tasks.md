# Tasks: Format Handoff Eval

## Completed

- [x] 1.1 Freeze hypothesis + decision criteria before any eval run (docs/plans/2026-06-10-format-handoff-eval-hypothesis-and-plan.md)
- [x] 1.2 Build 12 renderings of 4 real PDLC artifacts (F1 md / F2 md+front-matter / F3 DocLang via docling 2.98.0)
- [x] 1.3 Author eval pack: 6 scenarios, 34 assertions, all compile-checked under `grep -E`
- [x] 1.4 Build `tests/run-format-evals.sh` driver (Bash 3.2, opt-in, per-format isolation, kind-tagged aggregation)
- [x] 1.5 Build `tests/test-frontmatter-extraction.sh` (Eval 2) — fm_get 5/5 vs guard-grep 2/5 + real specimen
- [x] 1.6 Fix `tests/run-behavioral-evals.sh` stdin prompt delivery (variadic `--disallowedTools` swallowed the prompt)
- [x] 1.7 Run Eval 1: 54 inner calls, variance 3 — all three formats 100% on 102 assertion-evals each
- [x] 1.8 Round-trip fidelity check — DocLang drops content (14.8% postmortem, `<100ms` design budget)
- [x] 1.9 Verdict vs frozen criteria: DocLang REJECTED, front-matter UNPAUSED, markdown sole handoff format
- [x] 1.10 Stub stdin-regression guard + positive/negative controls (argv regression fails loudly, no hang)
- [x] 1.11 Code review (pr-review-toolkit:code-reviewer) — no high-confidence issues; full suite 54/54
