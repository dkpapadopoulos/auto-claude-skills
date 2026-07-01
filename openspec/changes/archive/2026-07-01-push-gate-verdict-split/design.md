# Design — Push-Gate Verdict Split (Phase B)

## Architecture

Three layers, cleanly separated:

1. **Status layer (unchanged).** `.completed` (composition walker) and the branch-ledger (`hooks/lib/branch-ledger.sh`) record "milestone reached" on Skill return. The PR #81 gate — deny only when a milestone is in the active chain AND neither `.completed` nor the ledger has it — is preserved verbatim. This is what guarantees no regression of the chain-reanchor false-block fix.

2. **Verdict layer (new read path).** The owned artifact `~/.claude/.skill-project-verified-<token>` (written by `project-verification`) is the only deterministic pass/fail signal we own. It gains a `sha` field = `git rev-parse HEAD` at verify time. A new fail-open library `hooks/lib/verdict.sh` interprets it:
   - `verdict_covers_head <proj_root>` → true iff the artifact `sha` equals HEAD or is an ancestor of HEAD on the current branch (`git merge-base --is-ancestor`). This does the branch-scoping the token-scoped artifact lacks.
   - `verdict_is_clean` → true iff `failed[]` empty AND `could_not_verify[]` empty AND `gate_gaming_status == "clean"` (identical predicate to `deploy-gate`'s local-verification-of-record).
   - `diff_touches_routing <proj_root>` → true iff the branch's diff vs its base (`git merge-base` with `origin/HEAD`/default branch; fallback `@{upstream}`; if no base resolvable → false, fail-open) touches `^(skills|config|hooks)/`.
   - `is_routing_repo <proj_root>` → true iff `config/default-triggers.json` exists (this is a skill-routing plugin repo).

3. **Gate layer (`openspec-guard.sh`).** In the existing `git push` case:
   - **Verify hardening (fail-open, always):** if `verdict_covers_head` AND NOT `verdict_is_clean` → DENY, naming the failing gate(s). SHA-mismatch/absent → no new behavior.
   - **Routing gate (fail-closed, scoped):** if `is_routing_repo` AND `diff_touches_routing`: require a clean verdict where `verdict_covers_head`. Absent/unrelated-SHA → DENY with remedy `Skill(auto-claude-skills:project-verification)`. Ancestor-but-stale (covers an older commit on-branch, clean) → fold into `_STALE_MSG`/`_WARNINGS` as advisory (allow), matching the existing branch-ledger staleness discipline.

The verdict is read **live at push time**, not snapshotted — see Decision D.

## Trade-offs

- **Fail-open verify hardening only denies on a test failure AT HEAD** (`sha == HEAD`, `failed[]` non-empty). It does *not* catch "the user ran only the external `verification-before-completion` and never our `project-verification`" — that path has no owned artifact → falls back to status. A failing verdict at an *ancestor* is treated as stale (a later HEAD may be fixed) and does not deny — a failure is authoritative only for the exact commit it was measured at. Accepted: closing the no-artifact gap would require an owned verdict for an external skill, which we cannot produce deterministically. The routing gate carries the deterministic teeth on the high-risk paths.
- **Routing gate adds friction to routing-path pushes** (must have run `project-verification` covering the routing changes). This is the intended new gate, always satisfiable by an owned skill, scoped to plugin repos, and delta-aware: a clean ancestor verdict is accepted only when routing files are unchanged since it (so a benign non-routing follow-up isn't re-blocked), but a routing change made *after* the verdict is an unverified delta and denies.
- **No SHA on a legacy artifact** → treated as mismatch → status fallback. Chosen over "honor SHA-less verdicts" precisely to avoid cross-branch/stale false-blocks.

## Dissenting views

- *"Also snapshot the verdict into a branch-ledger-style store so it survives new sessions."* Rejected (Decision D): snapshotting races `project-verification`'s parallel write and reintroduces staleness ambiguity; live-read is both simpler and more correct. Cross-session loss degrades to status fallback (fail-open), which is acceptable.
- *"Add a model-attested review-verdict recorder so review also gets a verdict."* Rejected: a self-reported verdict relocates the `done ≠ done` gaming surface without deterministic teeth — theater. Status-only is the honest floor; the routing gate provides the real teeth on high-risk paths.
- *"Make the routing gate generic (any repo with skills/ or config/)."* Rejected: would annoy unrelated repos; scoped to `config/default-triggers.json` presence.

## Decisions

- **A — SHA-freshness is load-bearing, and the FAILURE deny requires `sha == HEAD`.** A verdict is honored only when its `sha` covers HEAD, and a *failure* denial additionally requires the failing verdict to be exactly at HEAD (not merely an ancestor) — a failure is authoritative only for the commit it was measured at. This makes every new denial a *true* block and closes both false-block holes (cross-branch bleed, and an ancestor-FAIL blocking a fixed HEAD).
- **B — Routing gate: deny on absent-or-unverified-delta, warn on benign stale.** Deny when no clean verdict covers HEAD, or when a clean verdict is an ancestor but routing files changed after it (unverified routing delta). A clean ancestor verdict with *no* routing change since warns (advisory) rather than denies, so benign non-routing follow-up commits are not re-blocked. The freshness that matters is the verdict→HEAD routing delta, not merely ancestry.
- **C — Review stays status-only**, gap documented. Revival trigger: if a review-skipped-but-status-recorded push causes a real incident, revisit with an owned review verdict (likely a persisted `security-scanner` artifact, the Option-C path).
- **D — Live-read at push time, no new ledger.** Avoids the parallel-`project-verification` ordering race and naturally survives chain re-anchor (the artifact persists per token regardless of `.completed` resets).
- **E — Scoped to skill-routing plugin repos** via `config/default-triggers.json` presence, and the routing gate fires independent of an active composition chain.

## Deferred follow-ups

- **Routing gate requires `gate_gaming_status == "clean"` (via `verdict_is_clean`).** Consistent with `deploy-gate`'s local-verification-of-record precedent, but because the gate-gaming tripwire is documented false-alarm-prone (benign moves/renames/reorders), a routing push bundled with a benign test refactor could be hard-denied on a `suspect` false positive. Revival trigger: if this false-blocks a legitimate routing change in practice, loosen the routing-gate deny predicate to `failed[]` + `could_not_verify[]` empty only (a `verdict_passed` predicate) and demote `suspect` to the advisory `_STALE_MSG`, keeping gate-gaming advisory per its settled treatment.

## Implementation Notes (synced at ship time)

Two review-driven refinements to the upfront design (both from an adversarial gate-breaking review; Decisions A/B above reflect the as-built state):
- **Verify-hardening deny tightened from "covers HEAD" to "at HEAD"** (`verdict_sha_is_head`). The upfront design honored an ancestor FAIL as covering; review showed that denies a fixed HEAD (false-block). A failure is authoritative only for the commit it was measured at.
- **Routing gate made delta-aware.** The upfront "warn on any ancestor-clean verdict" allowed unverified routing changes made *after* the verdict (bypass). As-built: an ancestor-clean verdict is accepted only when routing files are unchanged since it (`verdict_routing_delta`); a post-verdict routing change denies.
- Spec/design prose reconciled so the committed record matches the shipped `failed[]`-only verify-hardening condition (`could_not_verify`/`suspect` advisory).

## Out-of-scope

- An owned/deterministic **review** verdict (Option C). Deferred with the revival trigger above.
- Making `project-verification` run automatically; the user/model still invokes it. The gate only reads its artifact.
- Any change to the status layer (`.completed`, branch-ledger) semantics or the PR #81 deny logic.
- Cross-session verdict persistence.
