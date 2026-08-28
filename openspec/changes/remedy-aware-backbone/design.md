# Design: Remedy-Aware Gates on an Explicit Superpowers Backbone

## Architecture

### 1. Heredoc-aware segment scanner (`hooks/lib/git-command.sh`)

`_gc_split_segments` gains a heredoc state machine, Bash 3.2 compatible:

The scanner is restructured line-oriented (final design after adversarial review by Codex):

- Outside quotes and outside arithmetic context, `<<` (not `<<<`) starts heredoc-operator recognition: optional `-` (tab-strip), optional blanks, optional `'`/`"` quote, delimiter restricted to `[A-Za-z0-9_]+`, optional closing quote. The operator text stays part of the current segment.
- The heredoc OWNER (the segment's effective command word, via `_gc_segment_cmd_word` — group-opener unwrap + env/VAR=/sudo/nohup/command/exec/time prefix skip) decides the body's treatment, three-way:
  - **Data sinks** (`cat`, `tee`, `git`, incl. path forms): `(tabstrip, delimiter)` joins a FIFO pending list; at the line's end the scanner consumes whole lines as BODY — discarded, never emitted as segments, no budget cost — until a line equals the delimiter (exact for plain, leading-tabs-stripped for `<<-`), CR-stripped so CRLF pastes terminate. `git` is on the list so `git commit -F - <<EOF` keeps its commit (and mutate-then-push) classification.
  - **Known shell interpreters** (`bash`, `sh`, `zsh`, `dash`, `ksh`, `eval`, `source`, `.`, incl. path forms): the body EXECUTES, so no heredoc is registered — body lines scan as CODE and an embedded `git push` yields a real, precisely-detected segment (a blanket unbalanced here would substring-overmatch prose in the body).
  - **Anything else** (python/ssh/docker/unknown/empty): the body may execute in ways the scanner cannot enumerate — mark `_GC_UNBALANCED=1` (push detection falls back to the substring path) but still CONSUME the body to its known delimiter rather than truncating at the operator. Truncating dropped a real trailing `commit && push` from the segment stream (Finding 2 re-review); consuming keeps trailing top-level code reliably segmented so the precise `command_git_mutate_before_push` predicate runs on real code only — never on discarded body prose (no false-deny) and word-splitting each segment (whitespace-agnostic). The mutate-then-push deny therefore uses the precise predicate exclusively; there is NO raw-substring fallback (an earlier one had both a whitespace bypass and a body-prose false-deny).
- **Arithmetic contexts are depth-tracked** (`((`/`$((` … `))`): `<<` inside one is a shift, never a heredoc — without this, `echo $((1<<2)) && git push` registers a phantom heredoc that swallows the real push (an under-detect bypass; adversarial-review requirement).
- Fail-closed escape hatches (`_GC_UNBALANCED=1`): empty / non-`[A-Za-z0-9_]` / mixed-quote delimiter; end of input with an unterminated body; code-character budget exhausted.
- **Cost model**: char-scan is O(n²) in Bash 3.2, so CODE characters are budgeted at 4096 (beyond → unbalanced, byte-for-byte the pre-change >4KB behavior); heredoc bodies and fully-quoted continuation lines are consumed line-wise, O(n) total. The guard's precise-path size gate is raised to a 128KB sanity cap accordingly — this is what fixes the >4KB doc-write false denies (observed at command_len 6082/35036) and, as a side effect, large quoted #155-shape payloads. Measured post-change: 0.27s for a 3.5KB near-cap single-line command (same class as pre-change).
- **Bundled hardening (adversarial-review finding)**: `_GC_PRECISE_OK` is computed once in the guard and gates every precise-predicate consumer — including `command_git_mutate_before_push`, which previously ran on a size check alone and could act on an untrustworthy segmentation.

### 2. Achievable-remedy deny (`hooks/openspec-guard.sh`)

**Security-driven design (2026-08-28 review).** The first cut degraded the REVIEW/VERIFY *deny* to an advisory when the backbone was unavailable, reading availability from the registry cache. Code review found that CRITICAL: the cache is a plain 0644 file any Bash-tool turn can overwrite, so `{"available":false}` was a one-line agent-reachable lever to turn the gate off. That is exactly the deny→allow path the whole gate (SHA-binding, token symmetry, verdict-at-HEAD) exists to prevent. The corrected design **never suppresses the deny** based on a skill-availability signal.

- The bug being fixed is narrower than "the gate blocks a no-superpowers install": it is that the deny's *remedy text* said "invoke Skill(superpowers:X)", which such an install cannot do. The fix keeps the deny and, when the demanded skill is genuinely absent, APPENDS the achievable remedy (`_SETUP_HINT`: run /setup, or the human-only `ACSM_SKIP_PUSH_GATE=1`).
- `_skill_available <name>` resolves from **on-disk `SKILL.md` presence** — the same locations session-start discovers (`plugins/cache/<mkt>/<plugin>/[<version>/]skills/<name>/SKILL.md`, plus user skills) — never the registry cache. To make the message flip, an agent would have to delete the real installed plugin (destructive, session-breaking, detectable), and even then only the *wording* changes, never the decision. So there is no forgeable weakening: the cache is not consulted at all.
- Because availability only affects wording, the change is behavior-preserving for enforcement: all three deny sites (global fail-closed + chain-review + chain-verify) still deny identically; a partially-installed backbone still denies; and the deny is action-independent, so `gh pr merge` gets the same deny (no merge-silence gap — a separate finding the advisory-routing design would have had).
- `! _skill_available` is used only inside `if`/`&&` conditions (ERR-trap-exempt contexts), so it cannot trip the guard's `trap 'exit 0' ERR`.

### 3. Backbone-absent notice (`hooks/session-start-hook.sh`)

One line appended to the existing session-start summary when backbone skills are unavailable. No new injected block, no auto-invocation of /setup.

## Trade-offs

- Restricting delimiters to `[A-Za-z0-9_]+` under-parses exotic heredocs; they fall to the fail-closed substring path. Accepted: no-worse than today, deny-biased.
- Discarding bodies loses the ability to scan heredoc CONTENT for other checks; the publish-guard confidentiality scan operates on the raw command string, not segments, and is unaffected.
- Treating a missing availability flag as "available" means a genuinely backbone-less install still sees one hard deny on the very first session (before session-start has ever run). Accepted for safety of existing installs; the notice + next-session degradation covers it.

## Dissenting views

- The debate's installer advocate and re-grade seat both proposed vendor-neutral slot abstraction; the owner overruled it — superpowers is the deliberate backbone; ACS supplements rather than abstracts. Recorded so a reviewer does not "restore" slot indirection.
- The re-grade seat proposed bundling fallback DESIGN/PLAN guidance for backbone-less installs; rejected as guaranteed methodology drift.

## Decisions

- Bodies are discarded, not attached to segments (segments = code only).
- `_GC_UNBALANCED` is reused for heredoc failure modes rather than a new flag: every caller already treats unbalanced as "use fail-closed substring path"; no caller treats it as allow (verified before implementation; pinned by test).
- The availability flag covers only the two gating milestone skills; it is not a general capability registry (YAGNI).
