# Design: skill-rules.json Routing Interop (PR-X)

## Architecture

The translation is **deterministic** (string escaping + regex validation), so
it belongs in the build-time hook — this does not violate the org-hub principle
that the hook does "zero fuzzy work" (nothing inferential happens here).

**Integration point:** Step 5b of `session-start-hook.sh` already traverses
every cache plugin's `skills/*/SKILL.md` to build `FRONTMATTER_MAP`
(name → {triggers, role, phase, ...}). We piggyback on that same traversal:
for each plugin we also note its `skill-rules.json` (sibling to `skills/`, at
the resolved plugin/version root). After `FRONTMATTER_MAP` is built, a single
jq helper reads every collected `skill-rules.json` and, **only for skill names
whose frontmatter entry has no `triggers`**, injects a translated `triggers`
array back into `FRONTMATTER_MAP`.

Because both downstream consumers already read `$fm.triggers` —
Step 6 (defaults merge, line ~403) and Step 7 (custom-skill build, line ~455) —
no downstream wiring changes. Hub skills are not in `default-triggers.json`, so
they flow through Step 7 as customs and pick up the injected triggers there.

```
Step 5b traversal (cache plugins)
   ├─ collect SKILL.md paths  → _parse_frontmatter → FRONTMATTER_MAP
   └─ collect skill-rules.json paths (one per plugin, when present)
                                    │
                                    ▼
   _derive_skillrules_triggers (jq): for each rules file, for each skill,
     keywords → escaped, lowercased, boundary-wrapped ERE regexes
     intentPatterns → drop PCRE-only (denylist), keep survivors
                                    │
                                    ▼
   merge into FRONTMATTER_MAP.<name>.triggers  ONLY where currently absent
   + secondary bash compile-check drops uncompilable survivors, logs drop count
```

## Keyword → regex translation

Engine facts (verified in `skill-activation-hook.sh`): prompt `P` is lowercased
(`:78`); triggers are ERE-matched `[[ "$P" =~ $trigger ]]` (`:196`); a
boundary post-scan awards 30 pts on a word boundary vs 10 for a bare substring
(`:213-214`). The repo's house word-boundary idiom is `(^|[^a-z0-9])`, **not**
`\b` (`:1521` comment: "ERE avoids \b (BSD grep) and PCRE").

Per keyword: `ascii_downcase` → escape ERE metacharacters `. ^ $ * + ? ( ) [ ] { } | \`
→ wrap `(^|[^a-z0-9])<escaped>($|[^a-z0-9])`. Result: `"PR"` matches `open a pr`
but not `compression`; `"values.yaml"` matches the literal, dot escaped.

## intentPattern ERE validation

Two-stage drop:

1. **jq denylist** (primary, the proposal's stated mechanism) — drop any pattern
   matching PCRE-only constructs: lazy quantifiers (`.*?`, `.+?`, `*?`, `+?`,
   `??`, `{n,m}?`), backslash shorthand (`\d \w \s \D \W \S \b \B`),
   special groups / lookarounds (`(?:`, `(?=`, `(?!`, `(?<=`, `(?<!`),
   backreferences (`\1`–`\9`).
2. **bash compile-check** (secondary net) — each survivor is tested with
   `[[ x =~ $pat ]]` in a subshell; exit status 2 (regcomp failure) drops it.
   Catches malformed-but-not-PCRE patterns (e.g. unbalanced parens) that would
   otherwise make the activation hook emit a regex error on **every** prompt.

Reality: nearly every real intentPattern uses `.*?` / `(?!` and is dropped —
keywords are the load-bearing routing source. That is expected and logged.

## Trade-offs (accepted)

- **Most intentPatterns are dropped.** Accepted and by design — PCRE patterns
  cannot run under bash ERE; silently keeping them would misbehave (the
  `feedback_bash_ere_no_pcre_quantifiers` failure mode). Keywords carry routing.
- **Boundary-wrapped triggers score in the substring tier (10), not 30.** The
  engine's boundary post-scan sees word chars adjacent to the boundary-char the
  regex already consumed. Consistent with existing `(^|[^a-z])`-prefixed triggers
  in `default-triggers.json`; still routes correctly.
- **cache-only discovery scope.** Marketplace-registered-but-uninstalled plugins
  are not scanned — but installed plugins land in cache with their
  `skill-rules.json`, which is the actual bug surface. Widening discovery is a
  separate concern.
- **Frontmatter precedence.** A skill carrying both frontmatter triggers and a
  skill-rules entry keeps frontmatter (more specific/curated). skill-rules is a
  fallback, not an override.
- **Default-triggers interaction.** skill-rules triggers sit at the frontmatter
  tier (above `default-triggers.json`). If an external plugin shipped a skill
  whose name collided with a curated default skill AND provided skill-rules
  keywords, those keywords would override the curated triggers. Accepted:
  correct-by-design (frontmatter tier wins), the own plugin is skipped in
  discovery, and cross-plugin name collisions with curated skills are unlikely.

## Performance (measured)

Fork budget was the one substantive review concern. The translator is **2 jq
forks per skill-rules.json file** (extract records → in-process bash
compile-check → assemble map), independent of skill count, plus one map-merge
per file and one final `FRONTMATTER_MAP` merge. Measured on macOS `/bin/bash`
3.2 with a synthetic 30-skill single-file hub (2 keywords + 3 intentPatterns
each): translation-only delta (30 skills **with** vs **without** `skill-rules.json`,
same discovery cost both sides) is **~20 ms**. The larger cost of a big hub is
discovering the skills themselves (frontmatter parsing), which is
feature-independent. Well within the 200 ms session-start budget.

## Decisions

1. Fold into the existing Step 5b traversal + `FRONTMATTER_MAP`; no new plugin
   walk, no downstream consumer changes.
2. Lowercase keywords (engine lowercases the prompt; case-preserving would never
   match without an engine change — out of scope).
3. Denylist + secondary compile-check (protects the activation hook from
   erroring every prompt on a malformed survivor).
4. Triggers-only; `type`/`priority`/`enforcement` mapping deferred.
5. Drop count logged to stderr once per plugin when non-zero; stdout stays clean.

## Follow-up (noted, out of scope for PR-X)

Because nearly every real `intentPatterns` entry is PCRE (`.*?`, `(?!...)`) and
gets dropped, keyword quality becomes the sole routing signal for hub skills.
A follow-up could surface **which** skills lost the most patterns (a per-skill
dropped-pattern breakdown, not just a per-plugin count) so hub authors can
rewrite them as ERE or lean harder on keywords. PR-X logs only the aggregate
per-plugin count to stderr; the richer author-facing breakdown is deferred
(revival trigger: a hub author reports routing gaps traced to dropped patterns).

## Security posture

Read-only of local, already-installed plugin files. skill-rules.json content
becomes routing regexes only (never injected as instructions). No trifecta legs
added by this change. Malformed input degrades to empty triggers (fail-open),
never an abort — preserving the hook's fail-open contract.
