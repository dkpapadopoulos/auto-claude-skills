# Proposal: Remedy-Aware Gates on an Explicit Superpowers Backbone

## Why

Two measured defects punish every installer of this plugin (2026-08-27 session, all verified by experiment):

1. **Heredoc false blocks.** `hooks/lib/git-command.sh::_gc_split_segments` scans heredoc bodies as command text (its own header admits it). A documentation write whose heredoc body mentions `git push` classifies identically to a real push, and a markdown plan containing ` ```bash git add / git commit ``` ` fences followed by a legitimate push trips the unconditional mutate-then-push deny — the exact plan-writing workflow this plugin's own methodology prescribes. ~7 of 46 live deny records are heredoc-shaped; the class is live at v3.84.0, after the #155 fix that closed the adjacent quoted-newline class.

2. **Uninstallable remedies.** A fresh repo without obra/superpowers receives ZERO injected guidance ("let's build a user login feature" → 0 words; all phase slots route to unavailable `superpowers:*` skills and silently no-op) while `git push` is DENIED with remedy text naming `Skill(superpowers:requesting-code-review)` / `Skill(superpowers:verification-before-completion)` — skills that are not installed and can never run — and the same message teaches the permanent bypass (`ACSM_SKIP_PUSH_GATE=1`). Zero guidance in, hard block out, disablement taught. The 12 `global-failclosed` records in the production deny log are consistent with this shape.

Owner decision (2026-08-27): superpowers IS the intended phasing backbone — well-maintained; do not reinvent phases or skills, and do not abstract over the vendor. auto-claude-skills supplements that backbone with additional PDLC skills. Therefore the fix for defect 2 is dependency honesty, not vendor neutrality: when the backbone is absent, say so once, degrade gates to advisory, and make every remedy achievable ("install the backbone via /setup"), never a reference to an uninstalled skill.

## What Changes

1. `_gc_split_segments` becomes heredoc-aware: heredoc bodies are data, not command segments; interpreter-fed heredocs and unparseable forms stay fail-closed via `_GC_UNBALANCED`.
2. `hooks/openspec-guard.sh` gains a remedy-availability check: before a REVIEW/VERIFY deny whose remedy names a backbone skill, the guard consults registry availability (computed at session start); when the named skill is unavailable, the leg degrades to the existing warn-first advisory posture and the message's remedy becomes "install the superpowers backbone (run /setup)".
3. `hooks/session-start-hook.sh` emits one clear line when the backbone is absent ("core SDLC phases inactive — run /setup to install the superpowers backbone"). No new injected blocks.
4. Docs position auto-claude-skills as a supplement to the superpowers backbone; the hardcoded `superpowers:` references are declared correct-by-design.

## Capabilities

- **Modified**: `pdlc-safety` — push-gate segment classification (heredoc awareness) and deny-remedy achievability (advisory degradation when the backbone is absent).

## Impact

- `hooks/lib/git-command.sh` (scanner), `hooks/openspec-guard.sh` (remedy-availability + message text), `hooks/session-start-hook.sh` (backbone-absent notice, availability flag persistence), `tests/test-push-gate-detection.sh` + new heredoc cases, new tests for advisory degradation.
- No change to evidence/ledger acceptance rules (bridge strictness untouched). No new gate legs. No vendor abstraction layer.
