# Third-party SKILL.md frontmatter

Real frontmatter from a skill pack this plugin does not ship, used by
`tests/test-frontmatter-hyphen-keys.sh`. Fixtures come from the real producer on purpose: a
hand-written frontmatter only proves the parser agrees with the test author's idea of YAML.

| File | Source | Why it is here |
|---|---|---|
| `gstack-careful.SKILL.md` | `garrytan/gstack` @ `74512c2`, `careful/SKILL.md` (MIT) | a list-valued key (`triggers:`) directly followed by a HYPHENATED list-valued key (`allowed-tools:`), then a nested mapping (`hooks:`) |
| `gstack-review.SKILL.md` | same repo and commit, `review/SKILL.md` (MIT) | the control: the hyphenated list comes BEFORE `triggers:`, after a scalar hyphenated key (`preamble-tier:`) |

The frontmatter block is verbatim; the body is replaced by a one-line placeholder.
