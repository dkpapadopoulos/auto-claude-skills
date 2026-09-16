# Negative routing corpus

222 prompts that must NOT route to a cross-family consultation skill (`second-opinion`,
`panel`) or to the other two consultation contracts (`design-debate`, `synthesize`),
accumulated across the consultation-routing work (PR #253). It was the instrument that
caught every false dispatch that session; until 2026-09-16 it lived only in a session
scratchpad.

This is a **probe, not a suite test**: it runs the real activation hook 222 times.

## Run

```bash
H=$(mktemp -d); mkdir -p "$H/.claude"
echo '{}' | HOME="$H" CLAUDE_PLUGIN_ROOT="$PWD" /bin/bash hooks/session-start-hook.sh >/dev/null < /dev/null
bash tests/probes/negative-corpus/scan.sh "$PWD" "$H" tests/probes/negative-corpus/negatives.txt > after.txt < /dev/null
diff tests/probes/negative-corpus/baseline-0f86729.txt after.txt
```

Each output line is `<skills that fired>\t<prompt>`.

## The rule

Scan **before** a routing-adjacent change and **after**; the delta must be empty. The
baseline at `0f86729` is exactly 8 firing lines, all adjudicated as legitimate cross-skill
routings (explicit consultation requests that belong to a neighbouring contract). A new
line is a new false dispatch until proven otherwise; a vanished line is lost recall.

Known limit: the registry is built in a synthetic HOME, so plugin-discovered skills that
could outscore a consultation skill are absent (see memory note "routing A/B needs
available skills"). Grow the corpus by adding prompts from real false dispatches; never
delete lines — deprecate them in a comment block with a date and reason instead.
