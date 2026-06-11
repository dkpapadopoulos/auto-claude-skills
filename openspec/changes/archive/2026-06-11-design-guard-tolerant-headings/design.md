# Design: design-guard-tolerant-headings

## Architecture

Single-site change inside the existing PLAN-phase DESIGN COMPLETENESS block (`hooks/skill-activation-hook.sh` ~line 1460). The three section-presence checks move from `grep -q '^## <Header>'` to `grep -Eiq '^#{2,3} .*<word>[- ]<word>'`. The surrounding state-read, hint-emission, fail-open, and SKILL_EXPLAIN breadcrumb logic is unchanged.

## Dependencies

None. POSIX ERE only (`{2,3}` interval, bracket expressions) — verified under BSD grep on macOS including `LC_ALL=C` with multibyte (emoji) input. Bash 3.2 compatible; `bash -n` clean.

## Decisions & Trade-offs

- **Tolerant regex over YAML front-matter** (per match-scope-to-fix-size and the PR #48 eval verdict): both score 5/5 on the mutation fixtures, but front-matter costs ~6 generator-template edits, extra injected tokens, a permanent parser, and a metadata-vs-body drift surface. Front-matter stays re-paused with a sharpened revival criterion (typed field VALUES needed by a named consumer).
- **h2/h3 only, no leading whitespace**: `^#{2,3} ` rejects h4+ structurally (the 4th `#` fails the required-space position) and rejects CommonMark's 1-3 leading spaces. Accepted limitation for an advisory guard — false-"missing" merely nudges.
- **`.*` prefix tolerance**: a heading like "## Why nothing is out of scope" would count. Deliberate acceptance — an h2/h3 heading naming the concept is overwhelmingly likely to be the section, and the guard is advisory-only.
- **Missing-section hints keep the canonical form** (`add \`## Out-of-Scope\` section`): accept variants, nudge toward canon.
