---
type: gotcha
title: A/B-testing a hook needs a real checkout on both sides
description: Running a hook from a scratch copy repoints CLAUDE_PLUGIN_ROOT, so its libs fall open and the comparison differs for reasons unrelated to the diff.
tags: [hooks, testing, fail-open, push-gate]
source: hooks/openspec-guard.sh:381
timestamp: 2026-08-28T00:00:00Z
---

Comparing a hook across revisions must run BOTH sides from real checkouts:
`git worktree add --detach <dir> <sha>`. Never
`git show <sha>:hooks/openspec-guard.sh > /tmp/g.sh && bash /tmp/g.sh`.

The guard resolves `_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"`.
From a scratch path that becomes the scratch parent, `hooks/lib/*` is unreachable, the
`_OK` flags stay false, and every lib-backed leg falls open.

Measured at HEAD, identical guard source and identical payload, `CLAUDE_PLUGIN_ROOT`
unset:

    scratch copy   -> allow (no decision emitted)
    real checkout  -> deny

The scratch side always allows, so the artefact points the same way a genuine
enforcement regression does. Observed 2026-08-06 while reviewing the
`impl_evidence_detail` change: base=allow / head=deny read as a serious push-gate
regression, and redoing it from worktrees gave byte-identical output.

Applies to any hook, guard, or lib that sources siblings. Run each side more than once —
live `~/.claude` state is mutable and can drift between single runs — and
`git worktree remove` afterwards. See [[bash32-arithmetic-quoting]] for the other
silent-abort class in these hooks.
