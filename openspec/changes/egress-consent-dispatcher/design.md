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
        exactly one option labelled "Approve and send"; its preview = the package text
        a "Do not send" option (any preview on it never qualifies)
     PreToolUse  hooks/egress-consent-ask-hook.sh
        marker present AND tool_input has `answers` or `annotations` -> DENY (pre-answered)
        marker present AND agent_id non-null                    -> DENY (subagent cannot ask)
        marker present AND schema violated                      -> DENY (names the rule)
        marker present AND a record for this tool_use_id exists -> DENY (reused id)
        marker present, clean -> write ask SNAPSHOT
            .skill-egress-ask-<token>.<tool_use_id> = {digest, question, approve_preview_sha}
     PostToolUse hooks/egress-consent-receipt-hook.sh
        ask snapshot exists for this tool_use_id -> consume it FIRST (mv -> .used)
        answers[snapshot.question] == "Approve and send"
        AND tool_response.annotations[snapshot.question].preview is present (no fallback
            to the model-supplied option preview)
        AND sha256(that preview) == snapshot.digest == snapshot.approve_preview_sha
        -> write receipt .skill-egress-receipt-<token>.<digest>.<tool_use_id> {digest, ts}
        a repeated Post finds only .used -> writes nothing
  4. bash scripts/consult-dispatch.sh send <digest> [--model M]
        local validation first: strict own token, jq, frozen package re-hashes to <digest>,
          gitleaks over the package (exit 3 = findings -> refuse; other non-zero = scanner
          broken -> refuse as CANNOT VERIFY; binary absent -> announce and continue)
        then consume ONE fresh (<= 900s) receipt .skill-egress-receipt-<token>.<digest>.*
          by atomic mv -> .consumed; only a successful mv authorises the send
        a send whose outcome is uncertain reports "may have sent" and never restores the receipt
        codex exec -s read-only -C <empty mktemp dir> --skip-git-repo-check --ephemeral
                   --ignore-user-config --disable hooks --disable plugins
                   --disable memories --disable apps
                   -o <0700 run dir>/answer.md  - < frozen package
        prints the run dir

hooks/outbound-consent-hook.sh (PreToolUse Agent|Task|Bash, advisory, unchanged role)
  recognised cross-family dispatch NOT via consult-dispatch.sh
    -> systemMessage + one text-free record in ~/.claude/.egress-bypass-shadow.jsonl
  Bash text naming .skill-egress-receipt- -> systemMessage (possible receipt forge)
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
- Parallel sends: receipts are keyed `<digest>.<tool_use_id>`, so two approvals of
  identical packages are two receipts and authorise two sends; one approval authorises
  exactly one (the send that wins the atomic `mv`). Consumption happens after local
  validation and before execution — at-most-once attempts; a failed or uncertain send
  needs a fresh approval.

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
