# Outcome-ablation pilot and field census — evidence bundle

Everything needed to check the numbers in `../2026-10-04-frontier-value-results.md`.
Pre-registration: `../2026-10-04-frontier-ablation-prereg.md` (frozen at R2 + amendments A1–A5 before any run).

| Path | What it is |
|---|---|
| `harness/run.py` | Runs one task in three arms concurrently, each in a fresh isolated `HOME`; locks the vault while subjects run; grades afterwards. |
| `harness/hidden_runner.py` | Grader: runs a unittest directory against a repo copy in a child process, prints one JSON line. Only a test that ran and passed counts; skips, import failures, zero tests and count mismatches score 0. |
| `harness/test_hidden_runner.py` | Ten tests pinning those guarantees (mutation-checked). |
| `harness/validate_tasks.py` | Fixture validity gate, legs 1–5. |
| `harness/install_tasks.py` | Splits fixtures into subject repo + vault and writes the frozen manifest. |
| `harness/analyze.py` | The pre-registered analysis (exact paired sign-flip test, exact McNemar, exact sign test on cost). |
| `harness/AUTHORING_PROMPT.md` | The frozen fixture-authoring brief. |
| `data/manifest.json`, `data/gate.json` | Hashes frozen before the first run; per-fixture gate results. |
| `data/fixtures.tar.gz.b64` | The 16 fixtures (repo, hidden tests, reference solution, wrong fix, mapping), as base64 text: `base64 -d -i fixtures.tar.gz.b64 > fixtures.tar.gz` (SHA-256 of the archive `134943d4be1b2b45fd320485d2dd7a40d1443eea6fee7599ae466535a504421d`). Text, not a binary, on purpose — see the results document §2: one tracked binary file disables this repo's publish guard. Spent: they hit the ceiling. |
| `data/runs-<model>.jsonl` | One scored run per line (96 runs). |
| `data/analysis-<model>.txt` | `analyze.py` output as produced. |
| `data/labels.json` | Labeller confusion matrix, kappa, consensus-by-outcome, per-skill counts, and the replay counts (transcribed). No prompt text. |
| `data/run-observations.json` | Per-run routing-block contents (header, MUST INVOKE target, routed and invoked skills), lines changed, guard-file writes, and run-log times. |
| `data/census.json` | Field-census aggregates. Counts only; no prompt text. One field listing privately named skills was removed. |
| `census/*.py` | The census, sampling and replay scripts. They read local transcripts and must write only outside any git repository. |
| `codex/*.txt` | Codex's two reviews and the prompts that produced them (absolute path prefixes stripped from one). |

To re-run: copy `harness/` to a scratch directory outside any repository, unpack the fixtures into
`selected/`, run `validate_tasks.py selected` (it writes the `gate.json` that `run.py` reads for expected
test counts), create `homes/A0|A1|A2` as the pre-registration describes (A2 needs the plugin caches and a
pre-built registry), then `install_tasks.py <ids>`, then `run.py <model> <task>` one task at a time, then
`analyze.py <model>`. Run `python3 test_hidden_runner.py` first.
The labelled prompt sample is deliberately not included: it is private text.

**The scripts here are not byte-identical to the ones that ran.** `data/manifest.json` holds the hashes of
the versions that ran. After the runs: absolute home paths were rewritten to `~`-relative ones; and a code
review led to fixes in `hidden_runner.py` (skips, import failures and sub-test failures were mis-scored;
pinned by `harness/test_hidden_runner.py`), `run.py` (grader timeout, kill escalation, a stricter
manipulation check, a single-invocation lock), `analyze.py` (Holm output, usage-less runs excluded from
cost, unrounded p-values) and `census/sample.py` (refuses to write prompt text inside a repository).
All 96 runs were re-graded with the fixed grader: 96 of 96 hidden verdicts and 96 of 96 visible verdicts
are identical, and all 16 untouched starting repos fail with scores inside 0–1.

Known and not fixed: the grader runs subject code in the owner's account, so a subject that set out to
attack the grader could still forge a verdict; sibling arms' working copies are readable from a subject's
working directory; the manifest is not re-verified at grade time.

## Security note — read before re-running

`harness/run.py` launches each subject as `claude -p … --permission-mode acceptEdits --allowedTools "Bash …"`
with the caller's environment (minus `CLAUDE*` variables) and an isolated `HOME`. That is **not a
sandbox**: the subject has unrestricted Bash as the invoking user and can read or write anything that user
can, outside the throwaway `HOME` and working copy. It was acceptable for this pilot only because the
fixtures are small, benign, offline Python tasks and the runs were supervised; the mode-000 vault keeps
hidden tests from a *non-adversarial* subject, nothing more.

Before reusing the harness on anything less benign: run each arm in a container or VM (or Claude Code's
sandbox mode with writes limited to the working copy and egress blocked), narrow `--allowedTools` to
`Bash(python3:*)`-style entries, and build the child environment from an explicit allowlist instead of
copying `os.environ`. An environment allowlist was not used here because it was not verified to keep
keychain-based OAuth working; that check is the first step of any hardening.
