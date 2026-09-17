# Adopting the seed

Four steps. The seed becomes **your** files — this plugin never reads them again, never
rewrites them, and has no upgrade path that could overwrite your edits.

```bash
# 1. Copy it in (from the plugin's assets/design-seed/)
mkdir -p design && cp -R "<plugin>/assets/design-seed/." design/
rm design/ADOPT.md                      # this file is instructions, not a project file

# 2. Record where it came from
cat > design/adopted.json <<JSON
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
