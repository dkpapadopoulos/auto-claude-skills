# RED/GREEN harness for authorial-judgment (2026-10-27)

Eight synthetic drafts modelled on the skill's measured use (cover letter, recommendation,
essay, voice sample + post, product page, a good newsletter issue, a post whose plain
close is right). `fixtures/<scenario>/` holds the draft pointer and two asks that differ
only by the skill reference. `rubric.md` was fixed before any output was read.

Setup (isolated HOME so nothing touches `~/.claude`; see memory `isolated-home-headless-ab`):

```
R=$(pwd)   # this directory
mkdir -p "$R/home/.claude" "$R/cwd" "$R/out"
ln -sfn "$HOME/Library" "$R/home/Library"
jq 'del(.mcpServers) | .projects = {}' "$HOME/.claude.json" > "$R/home/.claude.json"
```

Run (5 reps, two arms, 8 scenarios = 80 calls, ~20 min at -P 5):

```
for sc in p1 p2 s1 s2 c1 c2 v1 x1; do for arm in control skill; do for rep in 0 1 2 3 4; do
  echo "$sc $arm $rep"; done; done; done | xargs -P 5 -L 1 bash "$R/run.sh"
```

`SKILL_DIR=/path/to/other/authorial-judgment bash run.sh …` runs the skill arm with a
different SKILL.md (the current-vs-candidate comparison). Outputs land in `out/` (not
committed). Judge every output by hand against `rubric.md`; `python3 -I editdist.py
draft.txt out.txt` reports word edit distance and numbers lost/added (reported, not scored).
Model: `sonnet` alias (claude-sonnet-5-5 on 2026-10-27), no tools, no slash commands.
