---
type: gotcha
title: Behavioral-eval subjects can Read the branch's own spec — sandbox denies writes, not reads
description: run-behavioral-evals.sh denies Edit/Write/Bash (and in CI WebFetch/WebSearch/Task/Agent) but never Read, so a subject evaluated on a branch whose committed spec/design describes the expected behavior can read the answer and false-pass the baseline; isolate the subject's cwd.
tags: [behavioral-evals, eval-contamination, red-green, testing, sandbox]
source: tests/run-behavioral-evals.sh:138-140; incident PR https://github.com/damianpapadopoulos/auto-claude-skills/pull/102
timestamp: 2026-07-10T18:40:00Z
---

The behavioral-eval runner's sandbox is write/act-shaped, not read-shaped:
`SANDBOX_TOOLS="Edit,Write,Bash"` (widened in CI to add
WebFetch/WebSearch/Task/Agent — `tests/run-behavioral-evals.sh:138-140`). **Read
is never denied.** An inner subject can therefore read any file in its cwd's
repo — including `openspec/changes/<feature>/specs/**` committed during DESIGN
in spec-driven mode, which literally describes the behavior being tested.

**How it bit (PR #102, assumption-audit):** the writing-skills RED baseline for
a product-discovery edit "passed" — but the subject had read the branch's own
committed spec (`openspec/changes/discover-assumption-audit/.../spec.md`) and
refused based on THAT, not on any capability of the unedited skill. A clean
re-run from an empty scratch directory (absolute paths into the repo for the
runner only, subject cwd outside the repo) gave the faithful result. Any
feature whose spec is committed on the branch under test leaks its expected
behavior into both RED and GREEN arms.

**Rule:** for RED/GREEN or baseline runs, launch the inner subject from an
empty cwd outside the repo (scratchpad), pass repo files by injecting their
CONTENT into the prompt (not paths), and treat a surprising baseline PASS as
contamination-until-proven: grep the subject's output for spec-specific
vocabulary it should not know, and grep the assembled prompt for the feature's
marker strings before trusting either arm. A second contamination vector in the
same incident: uncommitted worktree edits leaked the EDITED skill into the
"control" prompt — assemble control arms from `git show HEAD:<path>`, never the
working tree.

Related: [[bash32-arithmetic-quoting]] (same "passes in the wrong harness"
family — always test under the runtime that production uses).
