---
type: gotcha
title: A probe of hooks/lib run through the agent shell exonerates defects that are real in production
description: Agent shell commands run under zsh while hooks run the same lib under bash; a predicate can return the opposite answer, so a probe written to confirm a suspected defect produces a false all-clear and ends the investigation.
tags: [hooks, shell, zsh, bash, false-negative, debugging, instrumentation]
source: hooks/lib/git-command.sh
timestamp: 2026-09-07T16:35:00Z
---

`CLAUDE.md` already warns that the agent's shell is zsh, not bash, and lists the
splitting and glob differences that follow. This entry is about the *investigative*
consequence, which is easy to miss: **the shell mismatch turns a probe into a false
all-clear**, and a false all-clear closes an investigation rather than opening one.

## The measured failure

The push gate emitted an advisory claiming a single-ref push carried "more than one
ref". To check whether the predicate was wrong, the obvious move is to source the lib
and call the function on the same command string. Done as a normal agent shell command,
every case came back "single" — i.e. the guard looked correct and the advisory looked
like a fluke.

Re-run from a file with an explicit interpreter, same lib, same inputs:

    /bin/bash probe.sh   ->  'git push -u origin x 2>&1'  = partial   (the real behaviour)
    zsh       probe.sh   ->  'git push -u origin x 2>&1'  = single    (all cases "clean")

The defect was real and reproducible in production — it fired on three consecutive
pushes. The probe had simply been executed by a different interpreter than the hook.

## Why it is hard to notice

Both runs exit 0. There is no error, no warning, and no output shape that differs. The
only signal is a *contradiction*: the probe says the predicate is fine while the running
hook keeps emitting the advisory. If you trust the probe over the observation — the
natural direction, since the probe feels more direct — you conclude "not reproducible"
and stop.

## How to apply

- Write the probe to a file and invoke it as `/bin/bash probe.sh`. Never source a
  `hooks/lib/*.sh` predicate inline in an agent shell command and treat the result as
  authoritative.
- When shell sensitivity is itself the question, run the *same file* under both
  interpreters and compare; a divergence is the finding.
- When a probe disagrees with behaviour you have observed from the real hook, suspect
  the probe's interpreter before you conclude the hook is correct.
