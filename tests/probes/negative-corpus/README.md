# Negative routing corpus

224 prompts that must NOT route to a cross-family consultation skill (`second-opinion`,
`panel`) or to the other two consultation contracts (`design-debate`, `synthesize`),
accumulated across the consultation-routing work (PR #253). It was the instrument that
caught every false dispatch that session; until 2026-09-16 it lived only in a session
scratchpad.

This is a **probe, not a suite test**: it runs the real activation hook once per prompt.

## Run

```bash
H=$(mktemp -d); mkdir -p "$H/.claude"
echo '{}' | HOME="$H" CLAUDE_PLUGIN_ROOT="$PWD" /bin/bash hooks/session-start-hook.sh >/dev/null < /dev/null
bash tests/probes/negative-corpus/scan.sh "$PWD" "$H" tests/probes/negative-corpus/negatives.txt > after.txt < /dev/null
diff tests/probes/negative-corpus/baseline-3367e49.txt after.txt
```

Each output line is `<skills that fired>\t<prompt>`.

## The rule

Scan **before** a routing-adjacent change and **after**; the delta must be empty, except
for a change that deliberately fixes a line listed as open below. A new line is a new
false dispatch until proven otherwise; a vanished line is lost recall.

The current baseline, `baseline-3367e49.txt`, has 10 firing lines:

- **8 legitimate.** The same 8 as `baseline-0f86729.txt` (222 prompts), all adjudicated
  as legitimate cross-skill routings: explicit consultation requests that belong to a
  neighbouring contract.
- **2 known, open false dispatches.** Added 2026-09-17 from the round-7 held-out set
  (`tests/probes/consultation-acceptance/RESULTS-round7.md`), and not fixed:
  - `design-debate` on the "debate timer … rebuttal rounds" bug report. The bare word
    `debate` in its trigger matches, and that skill stays local.
  - `panel` on the HR "interview panel … each one of the reviewers' raw answers
    verbatim" prompt. The vendor-free clause matches, and that skill sends content to an
    external vendor, which since PR #255 still requires the user's approval. Left open
    on purpose on 2026-09-17: replaying 1,997 real prompts found none of this shape among
    the 588 a person typed, and a narrowing fix traded holes both ways. See
    `tests/probes/real-prompt-replay/README.md` for the measurement and the 2026-10-15
    revisit.

  A fix for either removes its line; the other lines must stay unchanged.

Known limit: the registry is built in a synthetic HOME, so plugin-discovered skills that
could outscore a consultation skill are absent (see memory note "routing A/B needs
available skills"). Grow the corpus by adding prompts from real false dispatches; never
delete lines (`scan.sh` reads every line as a prompt, so there is no comment syntax;
record a retired prompt's reason in this README instead).
