# RED/GREEN harness for authorial-judgment (2026-10-27)

Twelve synthetic drafts modelled on the skill's measured use (cover letter with and without
its gap, recommendation, essay, voice sample + post, product page, product update with a
quote and legal text, a good newsletter issue, a post whose plain close is right, a short
customer email, release notes). Fourteen scenarios: the eight RED ones (p1 p2 s1 s2 c1 c2
v1 x1), three Review Focus ones (c1b v1b r1) and three round-4 ones (q1 e1 d1). `fixtures/<scenario>/` holds the draft pointer and two asks that differ
only by the skill reference. `rubric.md` was fixed before any output was read.

Setup (isolated HOME so nothing touches `~/.claude`; see memory `isolated-home-headless-ab`):

```
export RED_WORK="${TMPDIR:-/tmp}/acs-red-2026-10-27"   # scratch stays OUTSIDE the repo tree
mkdir -p "$RED_WORK/home/.claude"
ln -sfn "$HOME/Library" "$RED_WORK/home/Library"   # symlink to the REAL Library: never rm -rf or rsync --delete through it
jq 'del(.mcpServers) | .projects = {}' "$HOME/.claude.json" > "$RED_WORK/home/.claude.json"
R=$(pwd)   # this directory
```

Run (5 reps, two arms, 14 scenarios = 140 calls, ~35 min at -P 5; r1 was run at 3 reps):

```
for sc in p1 p2 s1 s2 c1 c2 v1 x1 c1b v1b r1 q1 e1 d1; do for arm in control skill; do for rep in 0 1 2 3 4; do
  echo "$sc $arm $rep"; done; done; done | xargs -P 5 -L 1 bash "$R/run.sh"
```

`SKILL_DIR=/path/to/other/authorial-judgment bash run.sh …` runs the skill arm with a
different SKILL.md (the current-vs-candidate comparison). Outputs land in `$RED_WORK/out/` (never in the repo tree: a gitignored scratch dir under
`skills/` still trips the on-disk plugin-root lint). Judge every output by hand against `rubric.md`; `python3 -I editdist.py
draft.txt out.txt` reports word edit distance and numbers lost/added (reported, not scored).
Model: `sonnet` alias (claude-sonnet-5-5 on 2026-10-27), no tools, no slash commands.

Cleanup: `rm -rf "$RED_WORK"` once outputs are judged and recorded (the Library symlink inside
`home/` is removed with it; never follow it).
