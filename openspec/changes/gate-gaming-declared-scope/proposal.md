## Why

`gate-gaming-check.sh` is a text match over a diff. Its caller, `scripts/verify-and-record.sh`, chose that diff with a name glob (`'*test*' '*spec*' '.verify.yml'`), which selects any path containing "test" or "spec" — including evidence bundles under `docs/` and every file under `openspec/`. A skip decorator inside a string in such a file made the verdict `suspect`. `suspect` fails `verdict_is_clean`, which routing governance hard-requires, so every agent push of that branch was denied with the remedy "run project-verification until it reports a clean verdict" — which could never succeed (issue #332).

Measured over main's history with today's checker (1,190 first-parent commits, 536 with a diff the glob selects): 9 commits read `suspect`, 5 of those also touched a routing path and would be denied today, and on reading all 35 offending lines none is a weakened test. In 5 of the 9 every hit is outside the files the gate runs.

## What Changes

- **A repository may declare which paths the gate-gaming check reads**: an optional `gate_gaming_paths:` block list in `.verify.yml`. With it, the check reads those paths plus `.verify.yml`. Without it, the name glob applies exactly as before.
- **The declaration is read from the merge-base with the mainline**, never from the branch or the working tree. Editing it on a branch does not change the scope that branch is judged by.
- **A branch that changes the declaration cannot read `clean`** (a clean result becomes `suspect`), unless every path declared at the merge-base is still declared. The change decides what later branches are checked against, so it is never cleared without a person. Adding a first declaration counts.
- **A declaration at the merge-base that cannot be applied leaves the check `unverified`.** It does not fall back to the name glob, because the glob can be narrower than what was declared. Unusable means: an inline list, a quoted entry, pathspec magic, an absolute or `..` path, whitespace in an entry, a duplicate key, or an entry that matches no file at the merge-base.
- **A `.verify.yml` that is a symlink at the merge-base declares nothing.**
- **The verdict records what happened**: `gate_gaming_scope` (`declared`, `default`, `unusable`, or `unverified`), `gate_gaming_paths`, and `gate_gaming_scope_change` (`none`, `widened`, `changed`).
- **This repository declares its own scope**: `tests/` and the two assertion scripts `tests/test-db-gate-score.sh` delegates to.

Not changed: the checker's patterns, `verdict_is_clean`, routing governance, and every deny text. A real skip marker on a real test file under the declared paths is `suspect` exactly as before.

## Capabilities

### Modified Capabilities

- `project-verification`: the gate-gaming diff scope may be declared by the repository, is read from the merge-base, and is itself protected against change.

## Impact

- `scripts/verify-and-record.sh` — scope resolution, the change rule, three new verdict fields, printed lines.
- `.verify.yml` — this repository's declaration.
- `skills/project-verification/SKILL.md`, `skills/project-verification/references/discovery-ladder.md` — the key and its rules.
- `skills/project-verification/scripts/gate-gaming-check.sh` — header comment only.
- `tests/test-gate-gaming-scope.sh` (new), `tests/fixtures/gate-gaming-scope/` (new), `tests/test-evaluator-surface.sh` (a source pin that named the old literal pathspec).

**This change's own branch is `suspect`, three times over**: it is judged by the name glob (the declaration is not yet at the merge-base), it adds skip-marker text to test files and to this specification, and it adds a first declaration. A person pushes it.

## What a declaration does NOT buy (measured, and pinned as test cells)

- **A new test file outside the declared paths.** A branch can add one and import it from a file inside them; its markers are not reported. The name glob reported them when the file's name contained "test". This is a real loss of detection for a conventionally named test, accepted in exchange for not reading documents as tests. Cell K1 measures the checker's blindness; it does not measure a loss of executed coverage (its scratch gate runs no test).
- **The merge-base is resolved from local refs.** Whoever can move the mainline ref chooses the base and with it the declaration. Moving it to HEAD already emptied the diff before this change (cell K2a); moving it onto a narrowing commit is the same primitive reaching the declaration (cell K2b).
- **Once a narrowing is merged, later branches are judged by it.** That is the design: the protection is that the narrowing branch itself is `suspect`. (Cell F7.)

These make the declaration a tripwire against careless weakening. It is not a boundary against a deliberate one, and neither was the name glob.
