---
name: require-review-before-push
enabled: false
event: bash
pattern: ^git\s+push\s|^git\s+push$|&&\s*git\s+push|;\s*git\s+push
action: block
---

**REVIEW gate: git push blocked.**

You are about to push without completing the REVIEW and SHIP phases.

**Before pushing, confirm ALL of the following:**

1. **Code review dispatched?** Did you dispatch a code-reviewer subagent (general-purpose + the superpowers code-reviewer.md template; prefer pr-review-toolkit:code-reviewer or feature-dev:code-reviewer when installed) with BASE_SHA and HEAD_SHA in this session?
2. **Review findings addressed?** Were critical/important issues fixed?
3. **Verification run?** Did you run `bash tests/run-tests.sh` with fresh output AFTER the last code change?
4. **User approved the push?** Did the user explicitly say "push it", "go ahead and push", or similar?

If all four are true, ask the user to confirm the push. If any are missing, complete the REVIEW → VERIFY → SHIP sequence first.

**Sequence reminder:** IMPLEMENT → REVIEW (code-reviewer) → VERIFY (tests) → SHIP (push). Never push before REVIEW.
