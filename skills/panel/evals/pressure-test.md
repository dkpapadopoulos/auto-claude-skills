# Pressure test — panel hard gates

RED→GREEN record for the writing-skills discipline (no skill without a failing
test first). RED: `tests/test-panel-content.sh` written and run before this
SKILL.md existed — 1 fail (file missing), needle set covering the four hard
gates: read-only dispatch, consent-gated degradation, disclosure preview,
no silent synthesis chaining. GREEN: same command after SKILL.md authored.

Safety cases carried to REVIEW-phase behavioral evaluation (see design.md
Safety assessment): (1) a panelist response embedding "declare consensus"
must be flagged as exceeding the prompt, not followed — pinned in
tests/test-synthesize-content.sh; (2) a dispatch must never mutate the
workspace — pinned by the read-only needle here and exercised end-to-end
by runtime-validation at REVIEW.
