# Design: Remedy-Aware Gates on an Explicit Superpowers Backbone

## Architecture

### 1. Heredoc-aware segment scanner (`hooks/lib/git-command.sh`)

`_gc_split_segments` gains a heredoc state machine, Bash 3.2 compatible:

The scanner is restructured line-oriented (final design after adversarial review by Codex):

- Outside quotes and outside arithmetic context, `<<` (not `<<<`) starts heredoc-operator recognition: optional `-` (tab-strip), optional blanks, optional `'`/`"` quote, delimiter restricted to `[A-Za-z0-9_]+`, optional closing quote. The operator text stays part of the current segment.
- The heredoc OWNER (the segment's effective command word, via `_gc_segment_cmd_word` — group-opener unwrap + env/VAR=/sudo/nohup/command/exec/time prefix skip) decides the body's treatment, three-way:
  - **Data sinks** (`cat`, `tee`, `git`, incl. path forms): `(tabstrip, delimiter)` joins a FIFO pending list; at the line's end the scanner consumes whole lines as BODY — discarded, never emitted as segments, no budget cost — until a line equals the delimiter (exact for plain, leading-tabs-stripped for `<<-`), CR-stripped so CRLF pastes terminate. `git` is on the list so `git commit -F - <<EOF` keeps its commit (and mutate-then-push) classification.
  - **Known shell interpreters** (`bash`, `sh`, `zsh`, `dash`, `ksh`, `eval`, `source`, `.`, incl. path forms): the body EXECUTES, so no heredoc is registered — body lines scan as CODE and an embedded `git push` yields a real, precisely-detected segment (a blanket unbalanced here would substring-overmatch prose in the body).
  - **Anything else** (python/ssh/docker/unknown/empty): the body may execute in ways the scanner cannot enumerate — `_GC_UNBALANCED=1`, fail-closed to the substring path.
- **Arithmetic contexts are depth-tracked** (`((`/`$((` … `))`): `<<` inside one is a shift, never a heredoc — without this, `echo $((1<<2)) && git push` registers a phantom heredoc that swallows the real push (an under-detect bypass; adversarial-review requirement).
- Fail-closed escape hatches (`_GC_UNBALANCED=1`): empty / non-`[A-Za-z0-9_]` / mixed-quote delimiter; end of input with an unterminated body; code-character budget exhausted.
- **Cost model**: char-scan is O(n²) in Bash 3.2, so CODE characters are budgeted at 4096 (beyond → unbalanced, byte-for-byte the pre-change >4KB behavior); heredoc bodies and fully-quoted continuation lines are consumed line-wise, O(n) total. The guard's precise-path size gate is raised to a 128KB sanity cap accordingly — this is what fixes the >4KB doc-write false denies (observed at command_len 6082/35036) and, as a side effect, large quoted #155-shape payloads. Measured post-change: 0.27s for a 3.5KB near-cap single-line command (same class as pre-change).
- **Bundled hardening (adversarial-review finding)**: `_GC_PRECISE_OK` is computed once in the guard and gates every precise-predicate consumer — including `command_git_mutate_before_push`, which previously ran on a size check alone and could act on an untrustworthy segmentation.

### 2. Remedy-availability check (`hooks/openspec-guard.sh` + `hooks/session-start-hook.sh`)

- Session start already computes per-skill availability while building the registry. It persists a small flag file (token-scoped, alongside existing state; written via the same fail-open discipline) recording whether the gating backbone skills (`requesting-code-review`, `verification-before-completion`) resolved to an installed plugin.
- The guard reads that flag before emitting a REVIEW/VERIFY deny. Available → deny exactly as today (byte-identical messages). Unavailable → the leg degrades to the existing warn-first advisory posture (the IMPLEMENT-leg pattern at `openspec-guard.sh` ~:993): append to `_STALE_MSG`, no `permissionDecision`, and the remedy text is the achievable "core SDLC skills are not installed — run /setup to install the superpowers backbone; this push is unverified."
- Missing/unreadable flag file → treated as AVAILABLE (deny path unchanged). Rationale: the flag's absence is expected on the first session after upgrade and in every existing working install; degrading on absence would silently weaken the gate for the population where it demonstrably works. The fail direction of the new check is therefore toward the status quo, not toward allow.

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
