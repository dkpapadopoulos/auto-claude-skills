# Egress Consent Dispatcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cross-family sends from `panel`/`second-opinion` are refused unless the user approved that exact package through `AskUserQuestion`.

**Architecture:** A sender script (`scripts/consult-dispatch.sh`) owns egress and refuses without a single-use, digest-bound receipt. Receipts are written by a PostToolUse `AskUserQuestion` hook, only for asks a PreToolUse hook recorded as clean. The existing observer becomes payload-first and writes a bypass shadow log.

**Tech Stack:** Bash 3.2, jq, shasum/sha256sum, codex-cli 0.154 (`codex exec`), gitleaks 8.30 (`stdin --exit-code 3`).

**Spec:** `openspec/changes/egress-consent-dispatcher/{proposal.md,design.md,specs/cross-family-panel/spec.md}`

## Global Constraints

- Bash 3.2 compatible; no associative arrays; unquoted arithmetic on validated numerics.
- New hooks do NOT use `trap 'exit 0' ERR`; every failure path is explicit, and every inability-to-check is announced (`systemMessage`), never silent.
- No shared-singleton token anywhere in this feature (hooks: `session_token_from_transcript`; dispatcher: `resolve_own_session_token_strict`).
- Digest = sha256 of bytes with trailing newlines removed; nothing else normalised. Single-sourced in `hooks/lib/egress-consent.sh`.
- Approve label is exactly `Approve and send`. Marker is `[egress-consent:<64 lowercase hex>]`. Receipt TTL 900 s.
- State files are flat in `~/.claude` (the GC is `find -maxdepth 1 … rm -f`): `.skill-egress-ask-<token>.<tool_use_id>[.used]`, `.skill-egress-receipt-<token>.<digest>.<tool_use_id>[.consumed]`, `.skill-egress-pkg-<token>.<digest>`. umask 077, write tmp + `mv`.
- No env-var overrides that change which binary runs or skip a check (tests use PATH shims). Only the diagnostic shadow-log path may be overridden (`EGRESS_BYPASS_SHADOW_LOG`).
- Hook test payloads are derived from the 2026-09-16 live capture shape (`tool_use_id`, `transcript_path`, `agent_id`, `tool_input.questions[]`, `tool_response.{questions,answers,annotations}`), never invented.
- Every hook invocation in tests: `< /dev/null`-safe (payload via printf pipe), run under `/bin/bash`.
- Dispatcher exit codes: 0 sent · 2 usage/unsupported · 3 CANNOT VERIFY · 4 NOT APPROVED · 5 MAY HAVE SENT · 6 secret-scan findings.

---

### Task 0: Baseline the negative routing corpus and commit it

**Files:**
- Create: `tests/probes/negative-corpus/negatives.txt` (copy of the 222-prompt file, sha256 `a2d12811…70d`)
- Create: `tests/probes/negative-corpus/scan.sh` (the scanner, unchanged logic)
- Create: `tests/probes/negative-corpus/baseline-0f86729.txt` (the 8 firing lines)
- Create: `tests/probes/negative-corpus/README.md`

- [ ] Copy the three files from the session scratchpad; verify sha256 of `negatives.txt` matches.
- [ ] README states: purpose, how to run (`bash scan.sh <root> <home-with-registry> negatives.txt`), the before/after rule (delta must be empty), and that it is a probe, not a suite test (222 hook runs).
- [ ] Commit `test: commit the negative routing corpus used as the routing gate`.

### Task 1: Strict own-session resolver

**Files:** Modify `hooks/lib/session-token.sh` · Test `tests/test-session-token-strict.sh`

**Produces:** `resolve_own_session_token_strict` → prints `session-<id>` and returns 0, or prints nothing and returns 1. `resolve_own_session_token` becomes `resolve_own_session_token_strict || cat singleton` (behaviour-identical).

- [ ] Write the failing test. Cells, each run under bash, zsh, and dash when present (dash: sourced by path, since it has no self-location):
  1. env id valid + transcript exists → prints `session-<id>`, rc 0
  2. env id valid + no transcript + singleton present → prints nothing, rc 1
  3. env id unset + singleton present → nothing, rc 1
  4. env id with `/` → nothing, rc 1
  5. control: `resolve_own_session_token` in cell 2 still prints the singleton value
- [ ] Run; expect FAIL (`command not found`).
- [ ] Implement:

```bash
resolve_own_session_token_strict() {
    local _id="${CLAUDE_CODE_SESSION_ID:-}" _t="" _tok=""
    if [ -n "${ZSH_VERSION:-}" ]; then
        setopt local_options no_nomatch 2>/dev/null
    fi
    case "${_id}" in
        ""|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    for _t in "${HOME}"/.claude/projects/*/"${_id}.jsonl"; do
        [ -f "${_t}" ] || continue
        _tok="$(session_token_from_transcript "${_t}")"
        [ -n "${_tok}" ] && { printf '%s' "${_tok}"; return 0; }
        break
    done
    return 1
}
resolve_own_session_token() {
    resolve_own_session_token_strict && return 0
    cat "${HOME}/.claude/.skill-session-token" 2>/dev/null
}
```

- [ ] Run the new test and the existing `tests/test-phase-attest-shell-portability.sh`, `tests/test-session-token-race.sh`, `tests/test-persist-state.sh`; all PASS.
- [ ] Commit `feat: add a strict own-session token resolver with no singleton fallback`.

### Task 2: Shared egress-consent lib

**Files:** Create `hooks/lib/egress-consent.sh` · Test `tests/test-egress-consent-lib.sh`

**Produces:**
- `EGRESS_APPROVE_LABEL`, `EGRESS_RECEIPT_TTL=900`
- `egress_sha256` (stdin → hex; shasum or sha256sum; rc 1 if neither)
- `egress_digest_stdin` (strip trailing newlines, then sha256)
- `egress_valid_digest <s>` / `egress_valid_id <s>` / `egress_valid_token <s>` (charset checks)
- `egress_ask_path <tok> <id>`, `egress_receipt_path <tok> <digest> <id>`, `egress_pkg_path <tok> <digest>`
- `egress_write_atomic <dest>` (stdin → `dest.tmp.$$` → mv, umask 077)

- [ ] Failing test: digest of `"a\n\n"` == digest of `"a"` ≠ digest of `"a "`; digest equals `printf a | shasum -a 256`; validators accept/reject (64 hex lowercase only; `toolu_ABC123`, reject `../x`); paths have the documented shapes; atomic write produces mode 600.
- [ ] Implement (digest core):

```bash
egress_digest_stdin() {
    local _c
    _c="$(cat)" || return 1
    printf '%s' "${_c}" | egress_sha256
}
```

- [ ] Tests PASS under `/bin/bash`; commit `feat: add the egress-consent shared lib`.

### Task 3: Ask hook (PreToolUse AskUserQuestion) — safety cases first

**Files:** Create `hooks/egress-consent-ask-hook.sh` · Test `tests/test-egress-consent-hooks.sh` (shared with Task 4)

**Consumes:** Task 2 lib; `session_token_from_transcript`.
**Produces:** ask snapshot JSON `{digest, question, ts}` at `egress_ask_path`.

Decision order (first match wins), only when the raw payload contains `egress-consent`:
1. no jq → announce "cannot inspect consent question; any send will be refused"; allow.
2. unparseable → announce; allow.
3. no marker in any question text → allow silently.
4. `tool_input` has `answers` or `annotations` → **deny** `pre-answered`.
5. `agent_id` non-null → **deny** `subagent`.
6. schema verdict ≠ ok → **deny** naming the rule (`multiple-marked-questions`, `duplicate-question-text`, `malformed-marker`, `multiple-markers`, `multiselect`, `marker-in-option`, `approve-label-count`, `approve-preview-missing`).
7. digest(approve preview) ≠ marker digest → **deny** `preview-digest-mismatch` (so the user is never shown a mismatched package).
8. no token from payload / invalid id → announce "no session identity; consent not recorded; the send will be refused"; allow.
9. ask or `.used` file exists for id → **deny** `reused-tool-use-id`.
10. write snapshot; allow silently. Write failure → announce; allow.

Schema verdict (single jq program, `$L` = approve label):

```jq
(.tool_input.questions // []) as $qs
| [$qs[] | select((.question // "") | contains("[egress-consent:"))] as $m
| if ($m|length)==0 then "none"
  elif ($m|length)>1 then "multiple-marked-questions"
  elif ([$qs[].question]|length) != ([$qs[].question]|unique|length) then "duplicate-question-text"
  elif ([$m[0].question | scan("\\[egress-consent:")]|length) != 1 then "multiple-markers"
  elif ($m[0].question | test("\\[egress-consent:[0-9a-f]{64}\\]") | not) then "malformed-marker"
  elif ($m[0].multiSelect // false) then "multiselect"
  elif ([$qs[] | (.header // ""), (.options[]? | (.label//""), (.description//""), (.preview//""))] | any(contains("[egress-consent:"))) then "marker-in-option"
  elif ([$m[0].options[]? | select(.label == $L)]|length) != 1 then "approve-label-count"
  elif (([$m[0].options[]? | select(.label == $L)][0].preview // "") == "") then "approve-preview-missing"
  else "ok" end
```

- [ ] Write failing cells (payload builder mirrors the live capture): clean ask → silent + snapshot written; each of rules 4–7 and 9 → deny with the rule name and NO snapshot; unmarked question → silent, no snapshot; no transcript_path → announce, no snapshot; no jq (PATH shim without jq, with a jq-relinked control) → announce.
- [ ] Run → FAIL (hook missing). Implement. Run → PASS.
- [ ] Commit `feat: deny forged or malformed egress consent questions`.

### Task 4: Receipt hook (PostToolUse AskUserQuestion)

**Files:** Create `hooks/egress-consent-receipt-hook.sh` · Test `tests/test-egress-consent-hooks.sh`

**Produces:** receipt `{digest, ts, tool_use_id}` at `egress_receipt_path`.

Order: prefilter on `egress-consent` → jq present → token + id valid → ask snapshot exists (else announce "no clean ask recorded; no receipt") → `mv ask ask.used` (consume FIRST; failure → announce, stop) → `answers[snap.question] == $L` (else announce "not approved; nothing will be sent") → annotation preview present (`(.tool_response|objects|.annotations|objects)[$q]|objects|has("preview")`; else announce) → digest(preview) == snap.digest (else announce) → write receipt.

- [ ] Failing cells: approve + matching preview → receipt exists with digest; "Do not send" → no receipt; approve + annotations absent → no receipt (NOT falling back to `tool_input` option preview); approve + annotation preview mismatching → no receipt; Post with no prior Pre → no receipt; **Post delivered twice → exactly one receipt, second run writes nothing** (resurrection); Pre+Post for two different ids with identical package → two receipts; `tool_response` as an array → announce, no crash, no receipt.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat: issue egress receipts only from a clean, approved, digest-matched answer`.

### Task 5: Dispatcher

**Files:** Create `scripts/consult-dispatch.sh` · Test `tests/test-consult-dispatch.sh`

**Consumes:** Task 1 strict resolver, Task 2 lib, Task 4 receipts.

`prepare <provider> <file>`: provider ≠ `codex` → exit 2; unreadable/empty file → 2; NUL bytes (`LC_ALL=C tr -d '\000' < f | cmp -s - f`) → 2; strict token missing → 3; freeze to pkg path; print digest and the exact ask shape and the send command.

`send <digest> [--model M]`: digest invalid → 2; jq absent → 3; strict token → else 3; pkg missing → 4 ("not prepared"); pkg re-digest ≠ digest → 3 ("frozen package altered"); gitleaks: absent → announce and continue, `stdin --no-banner --redact --exit-code 3` rc 3 → 6, other non-zero → 3; mode `consultation.egress_consent` (`warn` | anything else = enforce): warn → print `consult-dispatch: consent enforcement is OFF (egress_consent=warn)` and skip receipts; enforce → for each non-`.consumed` receipt for this token+digest with `now - ts <= 900`: `mv r r.consumed` and stop at the first success; none → 4. Execute:

```bash
_iso="$(mktemp -d)"; _out="$(mktemp -d)"; chmod 0700 "$_iso" "$_out"
codex exec -s read-only -C "$_iso" --skip-git-repo-check --ephemeral \
    -o "$_out/answer.md" ${_model:+-m "$_model"} - < "$_pkg" > "$_out/codex.log" 2>&1
```

rc 0 and non-empty `answer.md` → print run dir, exit 0; else print `MAY HAVE SENT` + log path + "a retry needs a fresh approval", exit 5.

- [ ] Failing cells (PATH shim `codex` records argv+stdin to a file; shim `gitleaks`): full happy path → rc 0, stub saw `-s read-only`, `-C <empty dir>`, stdin == package; second send → 4 and stub NOT invoked again; no receipt → 4, stub not invoked; stale receipt (ts-1000) → 4; receipt for other digest → 4; tampered pkg → 3; no `CLAUDE_CODE_SESSION_ID` but singleton present → 3 (and message says "could not verify", not "approve"); jq absent → 3; gitleaks shim exit 3 → 6 and receipt NOT consumed; gitleaks shim exit 1 → 3; gitleaks absent → proceeds with announcement; `warn` mode with no receipt → sends and prints OFF line; unsupported provider → 2; codex shim exit 1 → 5 and receipt consumed; two receipts for the same digest → two sends succeed, third → 4.
- [ ] Run → FAIL. Implement. Run → PASS. Commit `feat: add consult-dispatch.sh, the consent-enforcing cross-family sender`.

### Task 6: Observer — payload-first, local verbs silent, bypass shadow log

**Files:** Modify `hooks/outbound-consent-hook.sh` · Rewrite `tests/test-outbound-consent.sh`

- [ ] Failing cells: `node codex-companion.mjs status` / `result` / `cancel` / `setup` / `--help` → silent, no shadow record; `… task hi` → announce "outside consult-dispatch.sh — not consent-gated", one shadow record `{ts,schema_version:1,tool,shape,sidechain,token}` with NO command text; codex subagent → same, shape `agent:codex:codex-rescue`; `bash scripts/consult-dispatch.sh send <d>` → silent; Bash naming `.skill-egress-receipt-` → announce "touched egress consent state directly"; transcript-derived token used even when the singleton names another session (the reproduced flipping pair); never a `permissionDecision` (kept load-bearing assertion); local general-purpose subagent mentioning gemini → silent.
- [ ] Implement: pre-filter adds `*skill-egress-*`; token from `session_token_from_transcript` on payload `transcript_path` only; companion verb = first word after `codex-companion.mjs` with quotes stripped; local verbs list `status|result|cancel|setup|--help|-h|task-resume-candidate`; shadow write via jq -nc to `${EGRESS_BYPASS_SHADOW_LOG:-$HOME/.claude/.egress-bypass-shadow.jsonl}`, `umask 077`, rotate >2000 lines to last 1000; remove the consent-file freshness logic (its writer is retired).
- [ ] PASS; commit `fix: make the outbound observer payload-first and give it a bypass corpus`.

### Task 7: Wiring, GC, retirement

**Files:** Modify `hooks/hooks.json`, `hooks/session-start-hook.sh`, `tests/test-state-file-cleanup.sh` · Delete `scripts/record-outbound-consent.sh`

- [ ] Failing cells: hooks.json has PreToolUse and PostToolUse entries with matcher `AskUserQuestion` pointing at the two new hooks (parsed with jq, not grepped); session-start GC removes an 8-day-old `.skill-egress-receipt-session-dead.<d>.<id>` and keeps a same-age file for the current token; `scripts/record-outbound-consent.sh` absent and no file in `hooks/ skills/ scripts/ config/` references it.
- [ ] Implement: add `-o -name '.skill-egress-*'` to the find, plus `! -name ".skill-egress-*-${_SESSION_TOKEN}.*"`; `bash -n` and `/bin/bash -n` on the session-start hook; wire hooks.
- [ ] PASS; commit `feat: wire egress consent hooks, GC their state, retire the model-run recorder`.

### Task 8: Skills

**Files:** Modify `skills/panel/SKILL.md`, `skills/second-opinion/SKILL.md`, `skills/design-debate/SKILL.md`, `tests/test-second-opinion-content.sh`, `tests/test-outbound-consent.sh`

- [ ] Failing content cells (body only): panel and second-opinion contain `consult-dispatch.sh prepare`, `consult-dispatch.sh send`, `Approve and send`, `[egress-consent:`, "preview must be the complete package", "Codex's read-only sandbox can still read other files", `NOT APPROVED` / `CANNOT VERIFY` handling ("never retry by re-asking when verification could not run"), `egress_consent`; neither contains `record-outbound-consent`; design-debate points new dispatch paths at `consult-dispatch.sh`.
- [ ] Edit Step 3/4 (second-opinion) and Step 3/5 (panel): the Codex participant is sent by the dispatcher from the main thread, not via `codex-rescue`; keep existing asserted phrases (read-only, write-capable, gitleaks, mktemp -d, chmod 0700) true.
- [ ] Run `tests/test-second-opinion-content.sh`, `tests/test-outbound-consent.sh`, `tests/test-skill-content-coverage.sh`, `tests/test-consultation-routing.sh`: PASS.
- [ ] Re-scan the negative corpus with this worktree's registry: diff against `baseline-0f86729.txt` must be empty.
- [ ] Commit `feat: route panel and second-opinion sends through the consent dispatcher`.

### Task 9: Docs

**Files:** Modify `CLAUDE.md` (one Gotchas bullet), memory `consultation-routing-followups.md`

- [ ] Bullet: dispatcher-owned egress; receipts from user answers; pre-filled `answers`/`annotations` denial; strict identity; the argued #198 and warn-first exceptions; the agent-writable amendment; residual risks; regression test names.
- [ ] Commit `docs: record the egress consent boundary`.

### Task 10: Live end-to-end (real harness) — required before merge

- [ ] Temporarily wire this worktree's two AskUserQuestion hooks into `.claude/settings.local.json` (backup first, restore after, cmp).
- [ ] `prepare codex` a harmless package ("Reply with the single word OK."); ask the user with the real schema; user chooses Approve → receipt exists → `send` → rc 0, answer present.
- [ ] Negative live cell: ask again, user chooses "Do not send" → `send` → rc 4.
- [ ] Measure the `Other` case: ask the user to pick Other and type `Approve and send`; record the Post payload's `annotations`; if a receipt was written, that is a finding to fix before merge.
- [ ] Restore settings; record results in `openspec/changes/egress-consent-dispatcher/LIVE-E2E.md`.

### Task 11: Review and ship

- [ ] Full suite `bash tests/run-tests.sh` (weak evidence; required anyway).
- [ ] Parallel reviewers (code, silent-failure, security) + `codex adversarial-review`; reproduce every finding with a flipping pair before accepting or rejecting.
- [ ] project-verification → PR.
