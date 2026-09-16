# Design: egress-consent-dispatcher

## Architecture

```
panel / second-opinion (model turn)
  1. write package file (question + approved source material + read-only instruction)
  2. bash scripts/consult-dispatch.sh prepare codex <file>
        -> freezes a copy at ~/.claude/.skill-egress-pkg-<token>.<digest> (0600)
        -> prints <digest> and the exact AskUserQuestion shape to use
  3. AskUserQuestion  (strict schema — anything else is not a consent question)
        exactly ONE question carries [egress-consent:<digest>], in its question text only
        multiSelect false; question texts unique within the call
        FIRST option "Do not send" — the highlighted default, so a reflexive Enter declines
        exactly one option labelled "Approve and send"; its preview = the package text
     PreToolUse  hooks/egress-consent-ask-hook.sh
        marker present AND tool_input has `answers` or `annotations` -> DENY (pre-answered)
        marker present AND agent_id non-null                    -> DENY (subagent cannot ask)
        marker present AND schema violated                      -> DENY (names the rule)
        marker present AND a record for this tool_use_id exists -> DENY (reused id)
        FIRST, for any marked call: revoke every unused receipt for <token>+<digest>
            (asking again supersedes; a cancelled or failed ask leaves nothing stale)
        marker present, clean -> write ask SNAPSHOT
            .skill-egress-ask-<token>.<tool_use_id> = {digest, question, ask_ms}
     PostToolUse hooks/egress-consent-receipt-hook.sh
        ask snapshot exists for this tool_use_id -> consume it FIRST (mv -> .used)
        answers[snapshot.question] == "Approve and send"
        AND tool_response.annotations[snapshot.question].preview is present (no fallback
            to the model-supplied option preview)
        AND sha256(that preview) == snapshot.digest == snapshot.approve_preview_sha
        -> write receipt .skill-egress-receipt-<token>.<digest>.<tool_use_id>
               {digest, tool_use_id, ts, ask_ms}
        a repeated Post (snapshot already .used) -> ignored entirely: no receipt, no revoke
        any OTHER answer (decline, free text) -> record a VETO for the digest
            (.skill-egress-veto-<token>.<digest> = ms the decline was ANSWERED) and rename every
            unused receipt of the conversation to .revoked (latest answer wins; found live)
        an unverifiable answer (no snapshot, odd tool_response, bad preview) -> revoke the
            package's unused receipts; messages state what was actually withdrawn

hooks/egress-consent-turn-hook.sh (UserPromptSubmit)
  revoke every unused receipt of the conversation: an approval lives only in its turn
  4. bash scripts/consult-dispatch.sh send <digest> [--model M]
        private dirs FIRST (absolute TMPDIR, refused inside a git repository), then the
          frozen package is copied ONCE; digest, scan and send all use that copy
        local validation: strict own token, jq, the copy re-hashes to <digest>,
          gitleaks over the copy, from the isolated dir, env -u GITLEAKS_CONFIG[_TOML],
          --ignore-gitleaks-allow, empty ignore path (exit 3 = findings -> refuse; other
          non-zero -> CANNOT VERIFY; binary absent -> announce and continue)
        then consume ONE fresh (<= 900s) receipt whose ask_ms is NEWER than the digest's
          veto (i.e. asked after the last decline was answered), by atomic mv -> .consumed
        a send whose outcome is uncertain reports "may have sent" and never restores the receipt
        codex exec -s read-only -C <empty mktemp dir> --skip-git-repo-check --ephemeral
                   --ignore-user-config --disable hooks --disable plugins
                   --disable memories --disable apps
                   -o <0700 run dir>/answer.md  - < frozen package
        prints the run dir

hooks/outbound-consent-hook.sh (PreToolUse Agent|Task|Bash, advisory, unchanged role)
  recognised cross-family dispatch NOT via consult-dispatch.sh
    -> systemMessage + one text-free record in ~/.claude/.egress-bypass-shadow.jsonl
  Bash text naming .skill-egress-{receipt,ask,veto}- -> systemMessage (possible forge);
  reading the frozen package (.skill-egress-pkg-) is normal and not flagged
```

### Digest canonicalisation (the only one)

`sha256` over the bytes **with trailing newlines removed**, on both sides (dispatcher and
receipt hook). Trailing newlines cannot change meaning, and they are exactly what a model
copying a file into a tool argument is most likely to drop or add. Nothing else is
normalised: whitespace inside a package can change code, quotations and delimiters (Codex
review). Any other difference between the bytes the model put in the preview and the bytes
frozen by `prepare` produces a digest mismatch, which produces **no receipt**, which
produces a **refusal**.

**What the receipt does NOT prove (Codex round 2):** the harness returns the preview it was
*given*. Nothing observable to a hook shows how much of it the UI rendered — a UI that
truncates or collapses a long preview still returns the full value, and the hash still
passes. The guarantee is therefore **"the user approved the supplied preview, which is
byte-identical to what is sent, modulo trailing newlines"**, not "the user read every byte". The question text tells
the user the preview is the complete package; very large packages are a residual risk.

### Decline is the default option

Found in the live run (2026-09-16): two dialogs whose question text asked the user to pick
"Do not send" came back "Approve and send", with the approve option listed first. Whether
that was a deliberate choice or Enter on the highlighted default is not observable from the
payload (`duration_ms` is 0, no auto-continue timeout is configured). Either way, egress
must not be the default: the ask hook denies a consent question whose FIRST option is the
approve label (`approve-option-first`), and `prepare` prints the decline option first.

### Pre-filled `annotations` and the `Other` answer

`annotations[q].preview` is what the receipt hook hashes, and the tool schema lets the model
supply `annotations` just as it can supply `answers`, so the ask hook denies a marked call
carrying **either** key. The free-text `Other` answer is unmeasured: if a user types
`Approve and send` there, `answers[q]` equals the label, and whether the harness then returns
a preview annotation is not known. Measured before merge in the live end-to-end run; until
then the design relies on the annotation requirement, and the discriminator is recorded as
an open verification item rather than assumed.

### Token symmetry

Hooks derive `session-<transcript basename>` from their own payload
(`session_token_from_transcript`, no fallback); the dispatcher runs in the model's Bash turn
and uses a new **strict** resolver, `resolve_own_session_token_strict` in
`hooks/lib/session-token.sh` — identical to `resolve_own_session_token` minus its final
singleton fallback (which the existing function takes silently, so checking its output for
non-emptiness proves nothing). Neither side ever uses the shared singleton: it names
whichever session wrote last, so a receipt read under it could be another conversation's
approval. Unresolvable identity ⇒ the hooks write nothing and announce; the dispatcher
refuses (CANNOT VERIFY). Refusing here can block legitimate use on a surface that does not
export `CLAUDE_CODE_SESSION_ID`; the fix for that is identity transport, never borrowing
another conversation's approval.

The existing observer currently resolves model-side; reproduced 2026-09-16 with a flipping
pair (env var present ⇒ consent found; absent ⇒ singleton ⇒ false "NO recorded consent").
It moves to payload-first.

## Failure posture — an argued exception to #198

#198's rule ("a check that cannot run must never block, and must announce") was written for
gates on a PHASE, where a fail-closed check bricks unrelated work (every push in the repo).
This change applies it to the hooks and deliberately does NOT apply it to the dispatcher:

| component | cannot run ⇒ | why |
|---|---|---|
| ask hook | allow the question, announce | blocking a question blocks nothing dangerous; no receipt follows, so the send is refused downstream |
| receipt hook | write nothing, announce | an absent receipt is the conservative state |
| observer | allow, announce | observer by contract |
| **dispatcher** | **refuse**, with a message that distinguishes `NOT APPROVED` from `CANNOT VERIFY` | see below |

The dispatcher refuses when it cannot verify because: (1) its **scope** is only the
consultation it was invoked for — a refusal never blocks unrelated work, which is the harm
#198 exists to prevent; (2) its **question is authorization**, not phase evidence: "could not
check whether the user approved this send" is not a state in which sending is a reasonable
default; (3) the action is **optional**, with a same-family fallback. Irreversibility is a
weaker supporting reason (a push can disclose irreversibly too, and the push gate still
fails open). The escapes are the announced `consultation.egress_consent: "warn"` setting and,
outside the plugin entirely, the user running `codex` themselves — the `!` prefix does NOT
bypass checks inside this script. `CANNOT VERIFY` names the broken part (no jq, no own
session identity, unreadable receipt, broken secret scanner) so "ask again" is never offered
as the remedy for a broken recorder (Codex review).

## Warn-first — why the dispatcher refuses from day one

The repo's convention is that a deny is earned from a shadow corpus, because only data can
say how often a new deny stops legitimate work. This change is an **explicit exception**, and
the weakest point of the argument is stated first: `panel` and `second-opinion` are required
to migrate, so their behaviour does change. The exception rests on three things:

1. **The affected population is measured at zero.** 60 days, 1,518 transcripts: no
   cross-family send came from either skill. There is no false-block rate to estimate
   because there is nothing to block; waiting would collect no data either, since the
   old observer logged nothing.
2. **The refusal's cost is bounded by construction:** one re-ask, a same-family fallback,
   and an announced escape setting. The repo's deny-flip discipline exists for gates whose
   false block has no cheap remedy (a push that cannot ship).
3. **The retrofit population is untouched.** `/codex:rescue`, direct CLI use and proactive
   rescue keep today's behaviour.

A live end-to-end send through the real harness before merge is the substitute evidence
that the ordinary path does not false-block.

What IS a retrofit — denying cross-family dispatch that bypasses the dispatcher — stays
warn-first, and this change finally gives it a corpus (`.egress-bypass-shadow.jsonl`). Any
future flip is its own change with a pre-registered threshold; none is proposed here.

## Threat model and the agent-writable amendment

The defended failure is **a non-adversarial model skipping the ask** — a routing false
positive, or a model that treats being routed as consent. The receipt comes from a
harness-recorded user answer, and the one model-controlled shortcut in that channel
(pre-filled `answers`, measured to be absent at PreToolUse in a genuine ask) is denied.

Receipt files live in `~/.claude` and are therefore **agent-writable**. This is a conscious
amendment of the standing rule "never suppress a gate on agent-writable state": forging one
requires writing a specifically named file carrying a digest the model computed, which is a
deliberate, transcript-visible act, and the observer announces any Bash command that names
the receipt path (string-detection ceiling: variables, `bash -c`, and scripts evade it). This
design does **not** defend against a model that intends to forge. It is written down here so
nobody reads the gate as stronger than it is.

## Trade-offs

- One confirmation per send, and a re-ask after any failed send (consumption happens
  before execution; a receipt is never reusable).
- Only the `codex` provider is supported by the dispatcher initially. Another provider is
  refused as unsupported; the skill then asks the user how to proceed.
- `-C <empty dir>` removes the default workspace context (repo `AGENTS.md`, git
  discovery). It is **not** a filesystem boundary: Codex's read-only sandbox permits reads
  anywhere. The preview says so.
- The observer classifies command TEXT, so a command that merely mentions `codex exec`
  (a commit message, a heredoc) is recorded as a bypass — the #155 class. Harmless for an
  advisory observer, but any future deny-flip adjudication must discount such records;
  segment-aware parsing (as the push gate does) is the fix if that corpus is ever used.
- **Codex loads context of its own.** Measured live 2026-09-16 (A/B, twice, flags passed
  as an array — a zsh unquoted-scalar run first produced a false "flags rejected"
  result): a plain `codex exec` from an empty directory ran **18** user/plugin hooks and
  started MCP servers; with `--ignore-user-config` and `--disable
  hooks/plugins/memories/apps` it ran **0** of either and still reached the model. That
  context would have left the machine without appearing in any preview. A global
  `~/.codex/AGENTS.md` is not known to be excluded by these flags (absent on the
  measuring machine) and remains a residual risk.
- Approvals do not accumulate across asks: asking again about a package withdraws the
  earlier approval (needed so a cancelled re-ask, which fires no PostToolUse, leaves
  nothing stale). Only PARALLEL asks — both posed before either is answered — can yield
  two receipts and authorise two sends; a veto from a parallel decline still wins,
  whatever order the answers arrive in. One approval authorises exactly one send (the
  atomic `mv`). Consumption happens after local validation and before execution —
  at-most-once attempts; a failed or uncertain send needs a fresh approval.
- An approval lives only within its turn (UserPromptSubmit revokes it). Cost: a user who
  approves, lets the turn end, then says "go ahead" is asked again.

## Review rounds (2026-09-16)

Three reviewers (code, silent-failure, adversarial) reproduced every finding with a control
run. Fixed: a decline that did not reliably cancel an earlier approval (odd payload,
failed ask, cancelled ask, parallel answer order, a different package, a later prompt); the
package being read three times (TOCTOU between check, scan and send); the secret scan being
silenced by `GITLEAKS_CONFIG[_TOML]`, a `.gitleaks.toml`/`.gitleaksignore` in the caller's
tree, or an inline `gitleaks:allow`; control characters that could hide text in a preview;
hook JSON broken by control characters in model-written fields; false "the send will be
refused" claims; a hash failure reported as tampering; a scratch-dir failure reported as
MAY HAVE SENT and costing the approval; a relative TMPDIR; a TMPDIR inside a repository;
`--model` values starting with `-`; the observer flagging normal reads of the package.
Every fix has a regression cell and was mutation-checked. A fourth, fresh reviewer then
attacked the fix commit itself and found defects in it — a duplicate PostToolUse revoking
the approval it had just issued, veto ordering that depended on a whole-second boundary, a
false "hidden characters" refusal when the check could not run, an observer narrowing that
silenced glob commands, and an exported GIT_DIR causing a false refusal — all fixed, with
DEL, C1 controls and bidi overrides added to the hidden-character check.

Accepted residuals, not fixed:
- A "no" given as a plain (unmarked) question or chat reply inside the SAME turn does not
  withdraw an approval; the next user prompt does.
- Answers are looked up by exact question text; if the harness ever normalised that key, a
  genuine approval would be refused (false block, safe direction).
- Another plugin's PreToolUse `updatedInput` could inject answers after this hook checked
  the call; not testable here.
- A parallel ask that is CANCELLED (no PostToolUse) does not withdraw an approval given to
  its sibling asked at the same time; only the next user prompt does.
- Without perl (Time::HiRes) the clock falls back to whole seconds: a decline and a re-ask
  answered within the same second could order wrongly (false block, safe direction).
- The observer sees only Bash/Agent/Task, so Write/Edit of `.skill-egress-*` or of
  `skill-config.json` (the `warn` escape hatch — agent-writable config) is unobserved.
- `consult-run.*` answer directories are announced but never garbage-collected.

## Dissenting views

- **Codex (2026-09-16):** a nonce alone does not stop approving payload A and sending B;
  hashing the parent prompt binds the wrong object; initiator-scoping a PreToolUse guard
  moves the hole; warn-on-mismatch defeats the objective. All four accepted — they are why
  this is a dispatcher, not a guard. Codex also argued filesystem isolation beats consent
  ceremony. Accepted in part: `-C` + read-only is applied, true isolation is out of scope
  (it needs an OS sandbox the plugin does not own) and is listed as residual risk.
- **Not adopted:** gating proactive `codex-rescue`. It is 30 of 66 recent main-thread
  Agent dispatches and belongs to another plugin's contract; the user chose observe-only.

## Out-of-Scope

- `/codex:rescue`, direct `codex exec`, and proactive `codex-rescue` enforcement.
- The Codex stop-time review gate (a `Stop`-hook node process, never a tool call).
- A filesystem sandbox narrower than Codex's own read-only mode.
- Defence against a model that deliberately forges a receipt or an ask snapshot.
- Proof that the user read every byte of a long preview (see Digest canonicalisation).
- Any change to routing triggers, recall, or the frame-dependent ceilings.
- Gemini/OpenAI-API providers in the dispatcher.

## Decisions

1. Enforcement lives in the sender, not in a PreToolUse guard over inferred scope.
2. Consent = harness-recorded answer + clean-ask check + preview digest; model-run consent
   recording is retired.
3. Dispatcher refuses when it cannot verify (argued exception); hooks fail open and announce.
4. Escape hatch: announced `consultation.egress_consent: "warn"` (user's choice, 2026-09-16).
5. Bypass enforcement stays warn-first; the observer now writes the corpus.

## Verification plan

- Safety cases authored and **red** before implementation (deterministic, TDD): pre-filled
  forge, subagent ask, schema violations (two marked questions, marker in an option,
  duplicate approve label, multiSelect, duplicate question text), reused tool_use_id,
  repeated Post after send, annotation absent, identical packages approved twice, declined/other answer, preview/digest mismatch, receipt replay, stale
  receipt, tampered frozen package, missing token, missing jq, unsupported provider,
  escape hatch announced, bypass recorded, receipt-path Bash announced, local companion
  verbs silent.
- Hooks driven with payloads **derived from the 2026-09-16 live capture**, never invented.
- One live end-to-end send through the real harness (ask → receipt → send) before merge.
- Negative routing corpus scanned before and after: delta must be empty (baseline: 8 fire).
- External review: reviewer subagents + Codex adversarial review; every finding reproduced
  against the real hooks with a flipping pair before it is accepted or rejected.

## Acceptance Scenarios

See `specs/cross-family-panel/spec.md`.

## Capabilities Affected

- `cross-family-panel`
