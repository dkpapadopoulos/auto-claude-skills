# Frontend hint exposure probe (#412)

Instruments for the pre-registration `docs/plans/2026-10-31-frontend-hint-exposure-prereg.md`
(frozen in the commit that adds it on `main`). Nothing here is run on real transcripts before
that freeze. Tests: `tests/test-hint-exposure-probe.sh`.

| Script | What it does |
|---|---|
| `draw.py` | Draws the labelling corpus (D3): typed prompts with `.bak` copies merged, stratum A from each prompt's own routing block, a seeded uniform sample of the rest, weights, and the Q2 turn classes (D8). |

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
