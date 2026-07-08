# Proposal: skill-rules.json Routing Interop (org-hub PR-X)

## Why

Hub-published (and any externally-installed) plugins are discovered by the
session-start registry builder, but land with **empty triggers** whenever their
routing metadata lives in a sibling `skill-rules.json` rather than in SKILL.md
frontmatter. The builder ignores `skill-rules.json`, so those skills are
**unroutable** — they never score against a prompt and never surface in
activation context.

`skill-rules.json` is the routing convention several hub plugins already ship
(verified against real installed hub plugins whose files use the shape
`{skills.<name>.promptTriggers.{keywords,intentPatterns}}`). This is the
committed, independent follow-up (PR-X) recorded in the org-hub-connector
proposal — conflict-free with that change, landing after PR1 fixtures exist.

## What Changes

During registry build, when a discovered plugin skill has **no** SKILL.md
frontmatter `triggers`, fall back to the plugin's `skill-rules.json`:

1. **`promptTriggers.keywords` → word-boundary ERE regexes.** Each keyword is
   lowercased (the engine lowercases the prompt before matching), ERE
   metacharacters are escaped, and it is wrapped in the repo's house
   word-boundary idiom `(^|[^a-z0-9])KW($|[^a-z0-9])` — never `\b` (the repo
   deliberately avoids `\b` for BSD/PCRE portability).
2. **`promptTriggers.intentPatterns` → ERE-validated pass-through.** PCRE-only
   constructs (lazy quantifiers `*? +? ?? .*?`, shorthand `\d \w \s \b \B`,
   non-capturing groups / lookarounds `(?: (?= (?! (?<`, backreferences `\1`)
   are dropped via denylist; survivors are then compile-checked under bash
   `[[ =~ ]]` and any that still fail to compile are also dropped. The dropped
   count is logged to stderr, once per plugin, when non-zero.
3. **Frontmatter still wins.** skill-rules triggers apply only where SKILL.md
   frontmatter supplied none. No change to skills already carrying triggers.

Fail-open on every path (missing/malformed `skill-rules.json`, missing jq, no
matching skill entry): the skill simply keeps its empty triggers — never an
abort. stdout stays clean JSON; the drop-count log goes to stderr only.

## Capabilities

- **Modified: `skill-routing`** — registry build gains a `skill-rules.json`
  trigger-derivation fallback for frontmatter-triggerless discovered skills.

## Impact

- `hooks/session-start-hook.sh` — new deterministic translation folded into the
  existing Step 5b frontmatter traversal + `FRONTMATTER_MAP` build (~30 lines +
  one jq helper; +1 file read and +1 jq fork only for plugins that ship a
  `skill-rules.json`). Well within the 200ms budget (hub plugins are single-digit).
- `tests/test-registry.sh` — red-first fixtures: a cache plugin with
  `skill-rules.json` + a frontmatter-triggerless SKILL.md.
- No `config/default-triggers.json` / `config/fallback-registry.json` change
  (no curated-skill or capability-key change → no lockstep obligation).
- No new skill, no routing-fixture obligation (this is registry plumbing, not a
  new owned skill).

## Out of Scope

- Adding a marketplaces-dir scan. Installed plugins already land in
  `~/.claude/plugins/cache/`; the fix operates on the existing discovery scope.
- Mapping `skill-rules.json` `type` / `priority` / `enforcement` →
  role / priority (custom-skill defaults already cover role=domain; deferred).
- `fileTriggers` / any non-`promptTriggers` sections of `skill-rules.json`.
- `skills/project-verification/` and `hooks/lib/verdict.sh` (owned by a parallel
  session; untouched).
- org-hub PR2 tier wiring.
