# Outcome-ablation pilot and field census — evidence bundle

Everything needed to check the numbers in `../2026-10-04-frontier-value-results.md`.
Pre-registration: `../2026-10-04-frontier-ablation-prereg.md` (frozen at R2 + amendments A1–A5 before any run).

| Path | What it is |
|---|---|
| `harness/run.py` | Runs one task in three arms concurrently, each in a fresh isolated `HOME`; locks the vault while subjects run; grades afterwards. |
| `harness/hidden_runner.py` | Grader: runs a unittest directory against a repo copy, prints one JSON line. A load error or zero tests is never a pass. |
| `harness/validate_tasks.py` | Fixture validity gate, legs 1–5. |
| `harness/install_tasks.py` | Splits fixtures into subject repo + vault and writes the frozen manifest. |
| `harness/analyze.py` | The pre-registered analysis (exact paired sign-flip test, exact McNemar, exact sign test on cost). |
| `harness/AUTHORING_PROMPT.md` | The frozen fixture-authoring brief. |
| `data/manifest.json`, `data/gate.json` | Hashes frozen before the first run; per-fixture gate results. |
| `data/fixtures.tar.gz` | The 16 fixtures (repo, hidden tests, reference solution, wrong fix, mapping). Spent: they hit the ceiling. |
| `data/runs-<model>.jsonl` | One scored run per line (96 runs). |
| `data/analysis-<model>.txt` | `analyze.py` output as produced. |
| `data/labels.json` | Labeller confusion matrix, kappa, consensus-by-outcome, per-skill counts, and the replay counts (transcribed). No prompt text. |
| `data/run-observations.json` | Per-run routing-block contents (header, MUST INVOKE target, routed and invoked skills), lines changed, guard-file writes, and run-log times. |
| `data/census.json` | Field-census aggregates. Counts only; no prompt text. One field listing privately named skills was removed. |
| `census/*.py` | The census, sampling and replay scripts. They read local transcripts and must write only outside any git repository. |
| `codex/*.txt` | Codex's two reviews and the prompts that produced them (absolute path prefixes stripped from one). |

To re-run: copy `harness/` to a scratch directory outside any repository, unpack the fixtures into
`selected/`, create `homes/A0|A1|A2` as the pre-registration describes (A2 needs the plugin caches and a
pre-built registry), then `install_tasks.py`, then `run.py <model> <task>` per task, then `analyze.py <model>`.
The labelled prompt sample is deliberately not included: it is private text.

The scripts here differ from the ones that ran in one respect only: absolute home-directory paths were
rewritten to `~`-relative ones after the runs. The script hashes in `data/manifest.json` are of the
versions that ran.

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
