# Adopting the seed

Four steps. The seed becomes **your** files — this plugin never reads them again, never
rewrites them, and has no upgrade path that could overwrite your edits.

```bash
# 1. Copy it in. SEED_DIR is the directory holding THIS file: you opened it from
#    an absolute path (the routing hint that sent you here names one), so you
#    already have it. Nothing else does -- CLAUDE_PLUGIN_ROOT is not set in an
#    agent's shell, and this file is not in your repo. Arrived without a path?
#    This lists the installed copies, newest first; pick the version you run:
#      ls -dt ~/.claude/plugins/cache/*/auto-claude-skills/*/assets/design-seed
#    It covers the marketplace-cache layout only. A --plugin-dir or repo-checkout
#    install prints nothing, with no error -- in that case the seed is the
#    assets/design-seed/ directory of wherever the plugin actually lives.
SEED_DIR="${SEED_DIR:-<replace with the directory you read this file from>}"
# Three guards, all on the copy line itself because that is the line you paste:
#   `:?`            -- SEED_DIR unset or empty (otherwise "${SEED_DIR}/." is "/.")
#   tokens.css test -- SEED_DIR set to a real but WRONG directory. `/`, `$HOME` and
#                      the plugin root are all "set", so `:?` does not see them, and
#                      `-n` prevents overwriting, NOT traversing: without this test
#                      they each start a full recursive copy of that tree.
#   `-n`            -- never overwrite. If you ALREADY have a design/, your files
#                      win and you get a mixed tree, which is not an adoption --
#                      read your own design/styleguide.md instead of adopting.
# If you already have a design/, `-n` below keeps YOUR files and the copy exits
# non-zero with nothing on stderr -- and the natural reading of "adoption failed"
# is `rm -rf design`, which destroys exactly what `-n` just protected. So say it.
[ -e design ] && echo "you already have design/ -- read design/styleguide.md instead of adopting over it" >&2
test -f "${SEED_DIR:?set SEED_DIR to the directory holding this file}/tokens.css" || { echo "SEED_DIR is not the design seed (no tokens.css in it)" >&2; false; } && mkdir -p design && cp -Rn "${SEED_DIR}/." design/
# Removes the seed's copy of THIS file, never a design/ADOPT.md you already had
# (`-n` above preserves yours, so an unconditional rm would delete it).
cmp -s "${SEED_DIR:?set SEED_DIR to the directory holding this file}/ADOPT.md" design/ADOPT.md && rm -f design/ADOPT.md

# 2. Record where it came from. Guarded like the two statements above, and for the
#    same reason: `-n` preserves an adopted.json you already had, and an
#    unguarded `>` on the next statement would then destroy it -- this file calls
#    adopted.json the provenance record, so that loss is your preset and date.
[ -e design/adopted.json ] || cat > design/adopted.json <<JSON
{"preset": "quiet-dense", "version": 1, "adopted": "$(date +%Y-%m-%d)"}
JSON

# 3. Check it runs
bash design/checks/token-lint.sh --help
bash design/checks/token-lint.sh        # scans *.css under the current directory
```

**4. Point your agent instructions at it.** This is the step that decides whether any of
it gets used — a file nobody is told to read changes nothing. Add to your `CLAUDE.md` /
`AGENTS.md`:

```markdown
- UI work: read `design/styleguide.md` and reference tokens from `design/tokens.css`
  (roles, not literals). Open `design/reference.html` for the house composition. Run
  `bash design/checks/token-lint.sh` before claiming a UI change is done.
```

## Then make it yours

Using the default unchanged is a supported outcome — that is what "benefit immediately"
means, and `adopted.json` records the choice. But the palette is deliberately quiet and
dense; if your product is neither, change it:

- **Colour:** edit the role values in `tokens.css` (both themes). Keep the role *names* —
  everything references them.
- **Density:** pick one row height and delete the other.
- **Type:** the scale is six sizes on purpose. Replace the families before you add sizes.
- **Reference page:** once you have a real screen, make **that** your reference and delete
  `reference.html`. A page showing your own product beats a generic one.

After any token edit, re-run the lint and open the reference page in both themes. A
role you changed in light and forgot in dark is the most common mistake, and the only one
the eye catches faster than a test.

## Keeping `tokens.json` honest

`tokens.css` is the source of truth; `tokens.json` mirrors it for tooling. If you edit one,
edit both — or regenerate:

```bash
awk '/^:root \{/{b="light";next} /^:root\[data-theme="dark"\] \{/{b="dark";next} /^\}/{b="";next}
     b!="" && /^[ \t]*--/ {l=$0; sub(/^[ \t]*/,"",l); i=index(l,":"); n=substr(l,1,i-1); v=substr(l,i+1);
     sub(/;[ \t]*$/,"",v); gsub(/^[ \t]+|[ \t]+$/,"",v); printf "%s\t%s\t%s\n", b, n, v}' design/tokens.css \
| jq -Rn '[inputs|split("\t")|{theme:.[0],name:.[1],value:.[2]}]
          | {preset:"quiet-dense", version:1,
             light:(map(select(.theme=="light"))|map({(.name):.value})|add),
             dark:(map(select(.theme=="dark"))|map({(.name):.value})|add)}' > design/tokens.json
```
