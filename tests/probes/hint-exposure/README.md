# Frontend hint exposure probe (#412)

Instruments for the pre-registration `docs/plans/2026-10-31-frontend-hint-exposure-prereg.md`
(frozen in the commit that adds it on `main`). Nothing here is run on real transcripts before
that freeze. Tests: `tests/test-hint-exposure-probe.sh`.

| Script | What it does |
|---|---|
| `draw.py` | Draws the labelling corpus (D3): typed prompts with `.bak` copies merged, stratum A from each prompt's own routing block, a seeded uniform sample of the rest, weights, and the Q2 turn classes (D8). |
| `q1.sh` | Writes one config per route and variant from the appendix (only that route's triggers replaced) and replays the drawn prompts through `replay.sh --config` (D4). |
| `label.py` | One blind labeller (D2): the frozen rubric and shuffled batches of rows to a fresh headless `claude -p` per batch, in its own HOME with no tools, MCP servers or CLAUDE* variables; unanswered rows are re-asked once, then MALFORMED. |
| `score.py` | Resolves labels (D2), computes weighted precision and recall per route and variant, the bootstrap intervals and the three-valued D1 verdicts, the ranking, and the Q2 table (D8). Exit 3 is cannot-check. |

After the freeze, in order (`$D` outside any repository; seeds and cutoff from the frozen
registration):

```bash
P=tests/probes/hint-exposure
python3 "$P/draw.py" --since 2026-09-14T00:00:00Z --until "$CUTOFF" --seed "$SEED" --out-dir "$D"
python3 "$P/label.py" --draw-dir "$D" --prereg docs/plans/2026-10-31-frontend-hint-exposure-prereg.md --model claude-opus-5-5 --labeller L1
python3 "$P/label.py" --draw-dir "$D" --prereg docs/plans/2026-10-31-frontend-hint-exposure-prereg.md --model claude-sonnet-5-5 --labeller L2
# exit 4 from label.py means a labeller run failed: rerun that labeller, never adjudicate around it
python3 "$P/score.py" --draw-dir "$D" --variants docs/plans/2026-10-31-frontend-hint-variants.json \
  --labels "$D/L1.tsv" "$D/L2.tsv" --seed "$SEED" --worksheet "$D/worksheet.tsv"
# the owner labels worksheet.tsv (id and prompt only) into owner.tsv: <id><TAB>UI|NOT
git show "${BASELINE}:config/default-triggers.json" > "$D/base-config.json"
bash "$P/q1.sh" docs/plans/2026-10-31-frontend-hint-variants.json "$D/base-config.json" "$D" < /dev/null
python3 "$P/score.py" --draw-dir "$D" --variants docs/plans/2026-10-31-frontend-hint-variants.json \
  --labels "$D/L1.tsv" "$D/L2.tsv" --owner "$D/owner.tsv" --seed "$SEED"
```

Every output holds prompt text, so each script refuses an output directory inside a git
repository, writes its files with mode 0600, and prints counts and hashes only. Publish the
manifest's sha256, never the manifest: it lists transcript paths.

`HINT_LABELS` in `draw.py` is the leading label each hint has carried. It was read from every
version of `config/default-triggers.json` since 2026-08-25 (26 versions, none changed) with:

```bash
for c in $(git log --format=%h --since=2026-08-25 -- config/default-triggers.json); do
  git show "${c}:config/default-triggers.json" | jq -r '.methodology_hints[]
    | select(.name|test("frontend-playwright|frontend-quality-rules|design-seed"))
    | .name + "\t" + (.hint | capture("^(?<l>[A-Z][A-Z0-9 /-]+:)").l)'
done | sort | uniq -c
```

If a hint's label changes, add the new label to the tuple; never replace the old one, or rows
rendered under it fall out of stratum A.
