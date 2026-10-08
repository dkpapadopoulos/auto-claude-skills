# Design: the keyword path is measured, and what it admits alone is written down

## Architecture

`hooks/skill-activation-hook.sh::_score_skills` admits a skill when `trigger_score > 0 || name_boost > 0 || keyword_score > 0`. The keyword score is 20 for each keyword of six or more characters that is a substring of the lowercased prompt. The keyword is compared as written.

`scripts/keyword-path-audit.sh` never evaluates a regex or a substring. Every answer comes from running the hook against a one-skill registry built from the skill's shipped config entry, in a scratch home that is discarded before each run.

**Check 1, classes.** For each keyword, the prompt is the bare keyword and the skill is renamed to a neutral name, so its own name cannot admit it:

| keyword alone admits | triggers alone admit | class |
|---|---|---|
| no | either | `inert` |
| yes | yes | `covered` |
| yes | no | `keyword-only` |

A `keyword-only` or `inert` keyword needs a ledger row whose class matches. A `covered` keyword must have none.

**Check 2, fixture lines.** For each skill that carries keywords, every `MATCH` and `NO_MATCH` line of its routing fixture goes through the hook with the shipped entry under its real name. A selected `NO_MATCH` line is run again with the keywords removed, so the report says whether the keyword path selected it; it must be listed in the known file, and a listed line must still be selected. A `MATCH` line that is not selected is a finding.

**Controls, per skill, before any answer counts.** A nonsense prompt must not select the skill, under the neutral name and under the real one. The neutral name typed as a prompt must select it. The skill must have a fixture, and at least one of its `MATCH` lines must be selected. An `inert` answer stands only if a trigger that matches anything is selected on the bare keyword, or failing that on the keyword followed by nonsense words, where the keyword must still not admit. The hook leaves before scoring on a greeting, a prompt under five characters or a leading slash, and a keyword shaped like one of those would otherwise read inert whatever it does inside a longer prompt. If any of these fails, or any probe could not be run, the run exits 3 and prints no totals. Each job ends with a completion line, and a job without one refuses the run.

The prompt reaches the hook as a file. The hook stops waiting for stdin after two seconds, and a payload piped to it late was read as no prompt, which came back as "not selected".

Exit status: 0 measured and agreed, 1 measured with findings, 3 could not measure.

## Trade-offs

- **The class is measured on the bare keyword.** A keyword that is covered alone can still admit a prompt the trigger rejects, when it sits inside a longer word or after text the trigger forbids. `mine improvements` is covered and matches inside "determine improvements". Check 2 sees that, and only for the lines a fixture holds.
- **The decision column is a judgement nothing verifies.** The audit checks that a row exists and that its class is true. It cannot check that `recall` was the right call.
- **About 410 hook runs**: 42 for controls, about 230 for the classes, 142 for fixture lines. Skills are measured four at a time. The test file takes about a minute.
- **One skill per registry means admission only.** A keyword also adds 20 points, which can decide which of several admitted skills keeps a role slot. Neither check sees that. In the installed registry of 49 skills, 70 of the 72 `MATCH` lines reach their skill; the other two lose a slot to another skill and did so before this change.
- **Check 2 covers 14 of 36 fixtures.** A skill with no keywords has no keyword path, so its decoys are left to the regex test.

## Dissenting views

- **Key the population on trigger shape, as #310 did.** A trigger with `.*` joining two groups is where a constraint is most likely. Rejected: by that key `deploy-gate` and `improvement-miner` are exposed and neither has a keyword that admits alone, while `systematic-debugging`, `brainstorming` and `product-discovery` are not listed and have nine between them.
- **Record the decision in the config, next to the keyword.** Closer to where an editor looks. Rejected for now: it adds a field to a registry that two hooks parse and a fallback file mirrors, to hold text no hook reads.
- **Fix the two selected decoys in the same change.** Both fixes are one-line keyword deletions that the fixtures already ask for. Kept apart so that a change which alters no routing can land while #333's stage A is collecting.

## Decisions

1. Measure through the hook only. A check that re-derives the hook's predicate tests its own copy.
2. Rename the subject for check 1 and keep the real name for check 2. Check 1 isolates two paths; check 2 asks what a user would get.
3. Fail on a stale row as well as a missing one, so a reduction is banked and the ledger cannot keep a decision about a keyword that changed.
4. Refuse rather than report when a control fails. A dead hook makes every keyword read `inert` and every decoy read unselected.
5. List the two selected decoys as known instead of failing the suite on them. The suite is the local push gate, and one red file blocks every routing push.
