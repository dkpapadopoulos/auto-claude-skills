# A methodology hint's plugin paths must resolve where the hint lands

## Why

The `design-seed` methodology hint ships in both registries and renders on
DESIGN/IMPLEMENT prompts mentioning ui / components / screens / dashboards /
tokens. It named two plugin files by **repo-relative** path:

    assets/design-seed/ADOPT.md
    docs/design-seed-method.md

Neither exists in an adopting repo — they live in the plugin. Measured from a
scratch external git repo against the real activation hook: both paths MISSING,
and `CLAUDE_PLUGIN_ROOT` is unset in the model's Bash turn (measured
`<unset>`, zsh 5.9), so the reader cannot re-derive them either. `ADOPT.md`
itself opened with a literal `<plugin>` placeholder in its copy command, so even
a reader who found the file could not run step 1, and `docs/design-seed-method.md`
repeated the defect one hop on by naming `assets/design-seed/` relative to the
reader's repo.

This is the **#248 class** — a remedy an agent cannot execute is not a remedy —
and it went unnoticed for the same reason #248 did: the paths DO resolve in this
repo, where the plugin root and the project root are the same directory.

The hook already resolves `PLUGIN_ROOT` to an absolute path and already
substitutes `{{PLUGIN_ROOT}}` into a skill's `precondition` (#248). It never did
so for a `hint`. Four renderings were fixed then; the fifth was missed because it
is a different field read by a different loop.

## What Changes

- `hooks/skill-activation-hook.sh`: the methodology-hint renderer substitutes
  `{{PLUGIN_ROOT}}`, as the precondition renderer already did.
- `config/default-triggers.json` + `config/fallback-registry.json`: the
  `design-seed` hint carries `{{PLUGIN_ROOT}}` on its two plugin paths.
  `design/styleguide.md` in the same hint stays **relative** — it names the
  user's own adopted copy, not a plugin file.
- `assets/design-seed/ADOPT.md`: the `<plugin>` placeholder becomes `SEED_DIR`,
  the directory the reader opened the file from, with a discovery command for a
  reader who arrived without a path.
- `docs/design-seed-method.md`: its reference to the seed is resolved against
  the doc's own location, which a reader holding its absolute path can resolve.

## The path is emitted BARE, not single-quoted

#248 established that an emitted plugin path is single-quoted, because that text
is a shell command (`source '<path>'`) a human or agent pastes, and a path
containing `$( )` executed on paste. That reasoning does **not** transfer here: a
hint NAMES a file for the agent to read, and shell quotes handed to a Read tool
are literal characters that break it. The dominant consumer decides the form, and
the two sites are deliberately asymmetric. Both halves are pinned by tests, so
neither can be "made consistent" with the other by a later pass.

## Two destructive paths the fix made live, and what closed them

Making `ADOPT.md` reachable turns its copy command from dead text into something
an agent runs. Two latent hazards in it therefore became live, and both were
found by mutation testing rather than by reading:

1. **`cp -R "${SEED_DIR}/." design/` with SEED_DIR unset is `cp -R "/." design/`.**
   Measured: 123 GB of the filesystem root copied into a temp dir, with a hung
   test as the only tell. Introduced BY the fix — the `<plugin>` token it replaced
   was a literal and could not expand. Guard: `${SEED_DIR:?...}`, which catches
   empty as well as unset.
2. **Adopting over a `design/` the reader already has silently replaced their own
   `styleguide.md`.** Byte-identical in the pre-change version, so not introduced
   — but it goes from ~impossible to live. Guard: `-Rn`, which fails safe.

Both guards ride on the copy line itself, never on a neighbouring statement: the
realistic trigger is an agent pasting only that line. For the same reason the line
carries no `\` continuation — adding one broke the test's single-line extraction
into a syntax error, and the unit a reader pastes must be the unit a test can run.

**Three guards, because neither of the first two closed the class.** A review
round measured the traversal shape still reachable: `:?` fires only on
unset/empty, and `/`, `$HOME` and the plugin root are none of those, while `-n`
prevents overwriting rather than traversing — so into a fresh `design/` nothing
collides and the full walk proceeds. `test -f "$SEED_DIR/tokens.css"` closes it
by checking the directory IS the seed rather than merely set. The reasoning that
had accepted this as a residual gap ("step 3 runs the copied lint, which is
absent") was wrong: step 3 runs after the copy, so it is a detector, not a guard.

A fourth defect lived in the third guard's own interaction: `-n` preserves a
reader's existing `design/ADOPT.md`, and the next line's unconditional
`rm -f design/ADOPT.md` then deleted it. The remove is now guarded by `cmp -s`
against the seed's own copy.

Not claimed: `-n` is not POSIX and no GNU `cp` was available here, so whether GNU
returns 0 where BSD returns 1 on a skip is unmeasured.

## Impact

- `hooks/skill-activation-hook.sh`, both registry configs,
  `assets/design-seed/ADOPT.md`, `docs/design-seed-method.md`.
- No gate decision changes; a hint is advisory text.
- Capabilities: `skill-routing`, `design-foundations`.
