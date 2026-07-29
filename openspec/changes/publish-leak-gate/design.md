# Design: no private memory text on a public tracker (fix #174)

## Capabilities Affected

- `pdlc-safety` — a new outbound publication gate, sibling to the push gate.
- `improvement-mining` — the miner's evidence-citation contract changes from
  verbatim quote to `path:line`.

## Policy

**No verbatim private-memory text may appear in a published body. Cite
`memory/<file>.md:<line>` instead.**

Definitional, not a fitted heuristic — there is no deny-list to keep current and
nothing that silently goes stale. Rejected alternatives are recorded under
Decisions.

The rule loses nothing the quote was buying. The verbatim quote exists for the
A12 spot-check (`SKILL.md:59`) — catching a hallucinated citation. A `path:line`
citation makes that check *stronger*: the reviewer runs `sed -n '9p'` on the real
file instead of trusting an asserted string.

## Architecture

Two artifacts with one responsibility each. The engine decides; the hook enforces.

### `scripts/memory-leak-check.sh <body-file>`

Corpus resolution mirrors `mine-evidence.sh::memory_dir` exactly — main repo root
(`git rev-parse --git-common-dir`, worktree-safe) → slug →
`$HOME/.claude/projects/<slug>/memory`. `MEMORY_LEAK_CHECK_MEMORY_DIR` overrides,
for tests only.

The corpus is **every `*.md` in that directory, `MEMORY.md` included**. The index
is not exempt: its one-line hooks are memory text, and `mine-evidence.sh` skips it
only because it is not a *fact* row, which is an intake concern, not a
publication one.

1. Normalize: lowercase, every non-alphanumeric byte → space, collapse runs.
2. Build **16-word shingles per memory file**, resetting the word buffer at each
   file boundary. Not resetting fabricates matches that span the end of one file
   and the start of the next — observed in the prototype, and the reason the
   file-boundary case is a pinned test rather than a note.
3. Subtract shingles present in the repo's tracked content at HEAD
   (`git ls-files -z | xargs -0 cat`, normalized identically). Text already in the
   public repo is definitionally not a leak. This exemption is load-bearing: it
   cleared #160 and #169 outright.
4. Any surviving shingle → exit 1.

Exit codes: `0` clean · `1` leak · `2` usage · `3` cannot check.

**The report names locations only** — `body:<line> ← memory/<file>.md:<line>` —
and never echoes the matched text. A control that prints the private string hands
the model the exact bytes to paste again.

### `hooks/publish-guard.sh`

A new PreToolUse entry on the `Bash` matcher, **beside** `openspec-guard.sh`
rather than inside it. The push gate's fail-open ERR trap and its lib sourcing
order are load-bearing and stay untouched; multiple hooks per matcher is already
the established pattern (`Grep` has two).

- Prefilter `case "$_COMMAND" in *gh*) ;; *) exit 0 ;; esac`.
- Segment with `_gc_split_segments`, iterating with `IFS="${_GC_SEP}"` — the
  paired requirement for every caller of that splitter (#155).
- Match `gh issue create|comment|edit` and `gh pr create|comment|edit`; extract
  `--body-file`/`-F` and `--body`/`-b`.
- Flagged → `permissionDecision: deny`, naming the citation to use instead.

### Failure posture

The two failure directions are deliberately opposite:

- **Detection is fail-closed.** A hit always denies. This is a safety dimension:
  hard pass/fail, never averaged into a score.
- **Inability to check is fail-open.** No memory dir means there is nothing to
  leak. A missing `jq` means the command was never parsed, so there is no finding
  to act on. Both allow, and both say so — degradation is announced, matching the
  push-gate canary's posture rather than passing silently.

Documented string-detection ceiling, identical to the push gate's: heredocs,
`--body "$(cat f)"`, and `bash -c` indirection are not detected.

## Threshold: why 16

Measured over 27 real issue bodies against the live 164-file corpus, with the
public-content exemption applied:

| N | miner flagged | non-miner flagged |
|---|---|---|
| 8 | 7/8 | **8/19** |
| 12 | 7/8 | 2/19 |
| **16** | **7/8** | **1/19** |
| 20 | 7/8 | 1/19 |
| 25 | 7/8 | 1/19 |
| 30 | 5/8 | 1/19 |
| 40 | 3/8 | 0/19 |

16 sits at the start of a **plateau spanning 16–25** — full recall, minimum false
flags, and stable across a wide band. The number is read off a stable region, not
fitted to a single point (`feedback_heldout_before_adopt_detector`). N=8 would
deny 8 of 19 ordinary issues; N=30 begins dropping real leaks.

The lone non-miner flag at N=16 is **#131, and it is a true positive** — a 16-word
verbatim run from `push_gate_status_layer_no_cross_token_bridge.md`, confirmed by
per-file flattened search. **Measured false-positive rate at N=16 is 0 of 19.**

The non-miner population is the held-out set: it was never used to choose the
rule, and the rule was not tuned against it.

## The report/publish split

Redaction applies only where publication happens.

| surface | verbatim memory text | why |
|---|---|---|
| in-session report (Step 5) | **kept** | not a publication surface; the quote is most useful at the moment of the human gate |
| published issue body (Step 7) | **citation only** | public tracker |
| run-ledger issue (Step 8) | citation only | public tracker |

## Residual gap: the citation publishes the filename

A `memory/<file>.md:<line>` citation publishes the slug. Some slugs name an
organization, so the fix does not reduce exposure to zero.

Measured 2026-07-29 across all 164 files, by tokenizing each filename and
subtracting every token present in the repo's tracked content: the survivors are
dominated by ordinary English (`anonymize`, `validators`, `forbid`) and by
open-source project names already public in this repo (`grain`, `terrashark`,
`flywheel`). `oviva` and `scoutflo` do **not** survive — both already appear in
tracked content, so they are public already. The one clear private-org slug is
`project_zs_laguna_triage_parked`. Exposure is therefore roughly **1 file in
164**.

Accepted rather than closed, for two reasons. A filename is a single short token
reviewed at the Step 6 human gate — the failure mode in #174 was paragraphs of
prose sliding past unread, which a slug does not reproduce. And the only
mechanical fix is proper-noun matching against a maintained list, which is
precisely the fitted-heuristic failure mode the policy choice rejects: the
measurement above shows such a detector firing on seven harmless English words
while missing both names it was meant to catch.

Revisit if a client-named slug is ever actually published.

## Out-of-Scope

- **The miner's read access to memory.** It keeps full local read; the boundary
  is on publication, not intake.
- **`.claude/knowledge/`** — human-gated and PR-gated by design.
- **Secret-pattern scanning** (JWT/token/email/`$HOME`). Considered as a second
  net and dropped: the definitional rule already covers anything sourced from
  memory, and a pattern net invites the fitted-heuristic failure mode the policy
  choice exists to avoid. Revisit only if a leak is ever observed that entered a
  body from outside the memory corpus.
- **A deny-list of org/client terms** (`~/.claude/.redact-terms`). Same reason;
  it fails silently when stale.
- **CI enforcement.** Publication is a local act; a CI check would run after the
  fact.

## Acceptance Scenarios

### Scenario: a body carrying private memory text is denied

- **GIVEN** a memory corpus containing a 16-word run not present in tracked repo
  content, and a body file reproducing that run verbatim
- **WHEN** the model runs `gh issue create --body-file <body>`
- **THEN** the hook MUST emit `permissionDecision: deny`, MUST name the source
  `memory/<file>.md:<line>`, and MUST NOT include the matched text

### Scenario: the same fact cited by path is allowed

- **GIVEN** the same corpus, and a body citing `memory/<file>.md:9` with no
  verbatim run
- **WHEN** the model runs `gh issue create --body-file <body>`
- **THEN** the hook MUST produce no output and exit 0

### Scenario: text already public is not a leak

- **GIVEN** a run present in both the memory corpus and a tracked repo file
- **WHEN** the body reproduces it
- **THEN** the engine MUST exit 0

### Scenario: a run spanning two memory files is not a match

- **GIVEN** a body whose 16-word run exists only as the tail of one memory file
  concatenated with the head of the next
- **THEN** the engine MUST exit 0

### Scenario: the push gate is unperturbed

- **GIVEN** any `git push` command
- **WHEN** `publish-guard.sh` receives it
- **THEN** it MUST produce no output and exit 0

### Scenario: absent corpus allows

- **GIVEN** no memory directory
- **WHEN** any publish command is evaluated
- **THEN** the hook MUST allow, and MUST state that it could not check

## Decisions

1. **Cite, not redact.** Redaction via deny-list keeps verbatim quoting but fails
   silently when the list is stale; per-quote human confirmation is
   attention-policing, the control class that already failed here. Citation is
   definitional and strengthens the A12 spot-check.
2. **Hook, not SKILL.md prose.** A check the model is merely instructed to run is
   bypassed by drift or by any direct `gh` call. The hook also covers publication
   from sessions that never load the miner — which is how #131 happened.
3. **Separate hook, not a leg in `openspec-guard.sh`.** Single purpose,
   independently testable, and no risk to the push gate's fail-open trap.
4. **Remediate all 8 flagged bodies**, including human-authored #131. A rule the
   repo's own tracker violates is not a rule; and scoping remediation to the
   miner would imply the policy is about the tool rather than the surface.
   GitHub edit history preserves the originals — nothing is erased.
5. **`publish-guard.sh` joins the drift-canary manifest** as a parse-checked
   entry, on the same terms as `openspec-guard.sh`. It is a new enforcement
   surface; silent staleness is the failure mode the canary exists for.

## Trade-offs

- **Cost on a hit.** Building the tracked-content shingle set is the expensive
  step (~6.3 MB). It is built lazily — only once a candidate hit exists — so the
  cost lands only on the path that is about to deny anyway.
- **Friction on legitimate reuse.** An issue that deliberately restates a memory
  line at length is denied and must cite instead. Measured at 0 of 19 on real
  non-miner issues, so this is a narrow cost.
- **The ceiling is real.** Heredoc and `$(cat …)` forms are undetected. This is
  the same ceiling the push gate documents; closing it needs argv-level
  interception, which the hook interface does not offer.

## Dissenting views

- *"The three known leaks are benign, so gate-only would do."* Rejected: the
  measured 21-of-162 org-naming files are quotable by the same path, and the
  count of already-published leaks turned out to be 8, not 3. The margin between
  "benign by luck" and "not" is one run.
- *"16 words is arbitrary."* Partly fair — any threshold is a choice. The defence
  is that the plateau is 10 words wide and the held-out false-positive rate at
  the chosen point is zero, not that 16 is uniquely correct.
