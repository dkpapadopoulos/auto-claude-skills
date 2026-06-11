## Why

The PLAN-phase DESIGN COMPLETENESS guard grep-checked design docs with exact-match patterns (`^## Out-of-Scope`). The format-handoff eval (PR #48, 2026-06-10) surfaced a real specimen: an approved design doc using `## Out of Scope` (spaces) was scored as missing the section. The eval also showed a tolerant regex matches the full mutation set at zero convention cost, beating the YAML front-matter alternative that was re-paused.

## What Changes

The three design-guard heading greps in `hooks/skill-activation-hook.sh` are loosened to case-insensitive ERE tolerant of h2/h3 level, space-or-hyphen word joins, and prefix/suffix text (emoji, "& Non-Goals"). h4+ headings, body-text mentions, and leading whitespace before `##` intentionally still do not count. Two regression tests added to `tests/test-routing.sh` covering the mutation set positively and the non-heading exclusions negatively.

## Capabilities

### Modified Capabilities
- `skill-routing`: DESIGN COMPLETENESS section detection extended from exact prefix match to tolerant heading recognition (new ADDED requirement; exact canonical headers continue to match).

## Impact

- `hooks/skill-activation-hook.sh` — three grep patterns plus intent comment (advisory block only; no deny path touched).
- `tests/test-routing.sh` — `_write_design_fixture_raw` helper + 2 new tests (9 assertions).
- No changes to `hooks/openspec-guard.sh` (hard-deny boundary untouched).
