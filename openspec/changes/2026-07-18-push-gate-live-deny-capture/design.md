# Design — push-gate live-invocation capture

Issue #127. Diagnostic instrumentation for the intermittent
live-deny-while-replay-allows push-gate defect. **Zero change to any allow/deny
decision.** Hardened against a Codex adversarial sparring pass (findings folded
in below, tagged `[Cx#n]`).

## Goal

Make the next live-deny event self-documenting and, specifically, distinguish:

- **On-disk guard ran and denied** → capture *which gate* denied, plus a true
  replay showing whether the on-disk guard agrees with the live decision.
- **On-disk guard never ran** (stale in-process registration / drift) → its
  record is *absent* for that push → the smoking gun that redirects the
  investigation to the harness/caching layer.

## Architecture

Two pieces, deliberately split so capture code never touches the decision path
`[Cx1]`:

### 1. `hooks/openspec-guard.sh` — minimal inline additions only

- `_DECISION` shell var, default `allow`, set to `deny:<gate>` immediately
  before each of the seven existing deny `exit 0` sites (lines 138, 194, 206,
  222, 272, 318, 358). `<gate>` ∈ {mutate-then-push, chain-review, chain-verify,
  chain-verify-stale, global-failclosed, phase-enforcement, verify-hardening}.
- Once an invocation is classified push/merge (the block at line ~105), and
  only when `PUSH_GATE_CAPTURE_DISABLE != 1`: set `_PG_CAPTURE_ACTIVE=true`,
  export the payload the subprocess needs, and install the EXIT trap.
- The EXIT-trap function (defined inline — a function definition, not a runtime
  `source`, so no source-time failure can reach the decision path `[Cx1]`):

```bash
_pg_capture_on_exit() {
    trap - ERR        # [Cx2] a failing capture cmd must not re-fire `exit 0` ERR
    trap - EXIT
    [ "${_PG_CAPTURE_ACTIVE:-false}" = "true" ] || return 0
    (                 # [Cx2][Cx3] fully redirect: never leak a byte to stdout
        exec </dev/null >/dev/null 2>&1
        "${_PLUGIN_ROOT}/scripts/push-gate-capture.sh"
    ) || true
    return 0          # never alter the hook's exit code
}
```

The trap is installed (`trap '_pg_capture_on_exit' EXIT`) only inside the
push/merge block, so non-push git commands carry zero overhead and zero risk.
It fires on every exit path including the ERR trap's `exit 0` (verified Bash 3.2
semantics `[Cx2]`).

### 2. `scripts/push-gate-capture.sh` — the subprocess (all real work)

Receives payload via exported env (`PGC_*`): decision, action, command,
transcript, session token, guard path, plugin root, and the raw stdin `_INPUT`.

- **jq-gated** `[Cx7]`: exit 0 immediately if jq absent (diagnostic, fail-open).
- Compute: `command_sha` (sha256), `command_len`, and a **redacted command**
  `[Cx5]` — strip leading `VAR=val` env prefixes → `VAR=<redacted>`, redact
  `://user:pass@` / `://token@` in URLs. Full raw command only when
  `PUSH_GATE_CAPTURE_FULL_CMD=1`.
- Compute drift evidence: `guard_path`, `guard_cksum` (`cksum` of the running
  file `[Cx6]`), `plugin_version` (from `$_PLUGIN_ROOT`), `pid`.
- **On `deny:*` for a push/merge only** (rare, so the cost is bounded):
  - `ondisk_replay`: `PUSH_GATE_CAPTURE_DISABLE=1 bash "$guard_path" <<<"$PGC_INPUT"`,
    stdout captured. Empty ⇒ on-disk guard would ALLOW; a deny JSON ⇒ it agrees.
    This is the **true apples-to-apples replay** `[Cx4]` (identical stdin,
    payload-first token resolution) — recursion-guarded by the disable flag.
    Confirmed side-effect-free: the guard performs no state writes.
  - `gate_status_mirror`: `gate-status.sh` output captured into a var `[Cx3]`,
    stored as a JSON string. Labeled *mirror*, not *replay* `[Cx4]` (it uses
    empty-transcript token resolution and hardcodes "git push").
- Write **one** compact JSONL record `[Cx7]` (`jq -cn`) to
  `~/.claude/.push-gate-invocation-log`, created `0600` `[Cx5]`. Best-effort
  `capture_error` string field on any sub-step failure `[Cx6]`.
- **Rotate**: if the log exceeds 1000 lines, keep the last 500 (`tail`).

## Record shape (one JSONL line per push/merge invocation)

```json
{"event":"exit","pid":1234,"action":"push",
 "decision":"deny:global-failclosed","guard_path":"/…/openspec-guard.sh",
 "guard_cksum":"<cksum> <bytes>","plugin_version":"3.78.0","session_token":"…",
 "command_sha":"…","command_len":42,"command_label":"git push","command":"",
 "transcript_path":"…","ondisk_replay_decision":"deny|allow|incomplete",
 "replay_stdout_len":218,"replay_stderr":"…","gate_status_mirror":"…",
 "capture_error":null}
```

- **`command` is empty by default** — shell text cannot be robustly de-secreted
  (inline `-c http.extraHeader="Authorization: Bearer …"`, quoted suffixes), so
  the safe record carries `command_sha` + `command_len` + a coarse
  `command_label` (first two words after stripping env prefixes). Full
  (best-effort-redacted) text is opt-in via `PUSH_GATE_CAPTURE_FULL_CMD=1`.
- **`ondisk_replay_decision` is a POSITIVE classification, not raw output.** The
  replayed guard is itself fail-open, so an empty stdout cannot distinguish
  "genuine allow" from "crashed / early-exit". The guard prints a
  `__PGC_EVALUATED__` sentinel (under `PUSH_GATE_CAPTURE_REPLAY=1`) when it
  reaches the push-decision point; the classifier keys on that + a `deny`
  substring.

## What this proves

| live `decision` | `ondisk_replay_decision` | record present? | interpretation |
|---|---|---|---|
| deny:X | `deny` (agrees) | yes | on-disk guard genuinely denied — inspect gate X |
| deny:X | `allow` (sentinel, no deny) | yes | **live ≠ on-disk for identical input → drift confirmed** |
| deny:X | `incomplete` (+`capture_error`) | yes | replay never reached the decision point — NOT a drift signal; see `replay_stderr` |
| (push denied live) | — | **no record** | on-disk guard never ran → stale in-process code |

## Honest limitations

- If a stale in-memory guard denies, on-disk instrumentation cannot capture
  *what it decided* — only prove (by absence) the on-disk file did not run.
  Absence is not proof `[Cx6]`: it can also mean capture broke, wrong `$HOME`,
  or instrumentation not installed in the running plugin — hence `capture_error`
  and `guard_cksum`. A separate always-on PreToolUse probe *outside* the guard
  is the escalation if absence proves ambiguous, but it shares the same
  plugin-cache drift exposure, so it is deferred (YAGNI) until needed.

## Testing (TDD, deterministic)

- Allow path writes a record with `decision:"allow"`, no replay fields.
- A push-deny path writes a record with `decision:"deny:<gate>"` and populated
  `ondisk_replay`.
- Fail-open: unwritable log dir / missing jq / missing `gate-status.sh` never
  blocks or errors the guard, and never writes to stdout (assert stdout is
  exactly the one decision JSON, byte-for-byte).
- Redaction: `GH_TOKEN=x gh …` and `https://tok@host` never appear verbatim in
  the log; `command_sha`/`command_len` present.
- Recursion guard: replay subprocess with `PUSH_GATE_CAPTURE_DISABLE=1` writes
  no record and installs no trap.
- Regression: the existing push-gate suite's decisions are byte-identical
  (`tests/test-push-gate-*.sh`).
- Capture script is diagnostic-only → **not** added to `_GATE_ENFORCE_LIBS`;
  a test asserts it stays off the canary manifest.
