# Render the recorded verification verdict as a receipt a reviewer can read

## Why

`scripts/verify-and-record.sh` already measures a repo's declared gate and
records what happened: the commit the gate ran against, each check's outcome,
whether the tree was dirty, and the gate-gaming status. That record stays in
`~/.claude/` on the author's machine. The only thing that reaches a pull request
today is whatever sentence the agent chooses to write about it.

The plugin is installed on other people's repos. A reviewer there cannot tell
"the agent says the tests passed" from "the gate was run against this commit and
this is what it returned", because both arrive as prose. In this repo the agent
writes the suite line into most PR bodies (12 of the last 15 merged PRs,
counted 2026-11-16), but that is one owner's habit, nothing produces it, and
nothing ties the sentence to the measured record.

Source of the idea: two talks summarised in the owner's newsletter digest
(2026-11-10, "only one merge in 20 arrives with proof that it works";
2026-11-15, review as checking verification artifacts), sharpened by a
cross-model critique on 2026-11-16: a completion line in a PR body is a claim
unless something binds it to an execution. Neither source was measured here.

## What Changes

- **New `scripts/verify-receipt.sh`.** Reads the recorded verdict for the
  current commit and prints a short markdown receipt: commit, when and by what
  it was recorded, each check with its outcome, gate-gaming status, and a
  statement that it was produced on the author's machine and is not CI. It
  refuses, with the reason, when there is no measured verdict for exactly this
  commit or when the verdict was measured on a dirty tree.
- **`scripts/verify-and-record.sh` names the receipt command** in its closing
  output after it records a measured verdict, so the agent is told at the moment
  the evidence exists, in every repo, without a routing hint.
- **`skills/project-verification/SKILL.md`** says to put the receipt, verbatim,
  in the description of a PR opened or updated for that commit, and to render
  it again after any later commit.

Nothing blocks, no hook changes, and nothing is sent anywhere by the plugin.

## Capabilities

- `project-verification` (existing): three ADDED requirements. No new
  capability.

## Impact

- Users: a PR description can carry generated, commit-bound evidence instead of
  a sentence. Works on any host, since the receipt is text.
- The receipt is still pasted by the agent, and the verdict file is still
  writable from a shell. This is provenance, not a trust boundary; the receipt
  says so in its own text. External CI remains the boundary.
- Follow-up, NOT in this change: an opt-in `.verify.yml` setting that publishes
  the same result as a GitHub commit status, which is bound to the commit by the
  host and goes visibly stale on the next commit.
