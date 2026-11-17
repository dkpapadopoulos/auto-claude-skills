# #409 pasted-content shadow (stage 1): task plan

Design: rule R in `docs/plans/2026-11-17-paste-scoring-409-prereg.md` (B3, shadow only).
Constraints (owner): scoring only; never skip or change a state write; never change what is
displayed; boundary preserved; unterminated block cannot swallow typed text; TDD; worktree
`worktree-paste-scoring-409`; one fresh whole-branch reviewer at the end; no push/PR/GitHub
write without an explicit yes; never amend.

## Review Focus (each pinned by a cell in the owning task)
1. An id the harness might change (uppercase hex, 5+ chars): nothing stripped, record pairs 0 (T1, T2).
2. A multi-MB paste where the regex engine gives up: status `error`, nothing stripped, display and state unchanged (T1).
3. A wrapped prompt on an early-exit path (`[no-skills]`, leading `--`): no record and no work (T2).
4. No session token: no record, output unchanged (T2).
5. Typed words touching a block on both sides stay separate tokens after stripping (T1).

## T1 — parser lib `hooks/lib/pasted-content.sh` (TDD)
`PASTED_CONTENT_JQ_DEF` defines `paste_strip: string -> {status, openers, pairs, text}`:
- status `none` when the opener literal is absent (no regex runs);
- `capped` when openers > 16 (linear `indices` count; nothing stripped; measured: 1,000
  unmatched openers cost 0.5 s, 4,000 cost 3.3 s);
- `error` when the regex engine raises (nothing stripped);
- else `ok`: each pair (4-hex id, lazy to the first closer with the SAME id) -> "\n".
Cells: real fixtures (this session's paste-only brief with the escaped inner tag; a
typed-before-and-after PR #406 review paste from this repo); derived from them and labelled
derived (two blocks, unterminated, mismatched id, 17 openers); real negative (#409's issue
body quoting the bare tags); boundary (typed words either side stay separate tokens).

## T2 — shadow in `hooks/skill-activation-hook.sh` (TDD)
`_paste_shadow` runs after `_format_output` and `_emit_explain` (after every print and
state write). Only when the prompt contains the opener literal. In a subshell: lowercase
the stripped text, `_score_skills`, tentative phase, `_select_by_role_caps`; print the
selected names. Kept = full SELECTED names in the stripped selection, plus `_STICKY_SKILL`.
One text-free record per prompt in `~/.claude/.paste-shadow.d/` (new file, noclobber),
only when the opener literal is present AND a session token exists (as sticky-repeat).
Fields: schema_version 1, predicate_version 1, ts, session, prompt_count, kind
(`_PROMPT_KIND`), status, openers, pairs, process, process_kept, selected, kept, hidden,
sticky, displayed, block_chars. `ACS_PASTE_SHADOW=off` disables it (any other value =
shadow). A record with status `ok` and pairs 0 is the format-drift counter.
Cells: display byte-identical to the base hook; every `.skill-*` file identical turn by
turn to the base hook over the fixtures, base-vs-base control 0, strip-in-scorer mutant
differs; record fields match the dev replay for the two real fixtures; record carries no
prompt text; `off` writes nothing; sticky exemption; lib missing -> no record, hook output
unchanged; timing cell on 17+ openers stays under 2 s.

## T3 — corpus replay of the built hook
All 3,001 dev prompts through base vs built hook in fresh HOMEs: display and `.skill-*`
identical on all; the shadow's kept/hidden sets equal the Python simulation's on the 79.

## T4 — docs + spec
OpenSpec change (spec-driven preset), CHANGELOG line, routing-state rule bullet for the new
lib/record, and the hook comment. Then one fresh whole-branch reviewer; fix; report.
