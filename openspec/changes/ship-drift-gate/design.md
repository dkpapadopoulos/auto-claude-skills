## Context

`hooks/skill-activation-hook.sh` turns every composition entry that carries a `gate` into a `GATED:<type>:<marker>:<artifacts>:<line>` record, for PARALLEL and SEQUENCE entries alike, and renders the line only when the gate passes. For `artifact-presence` it passes when any `artifacts` pattern matches a path under the project root (`compgen -G`). REVIEW's drift-check entry used this; SHIP's did not.

## Decisions

1. **Same gate, same list, as REVIEW.** A SHIP fallback for a check REVIEW skipped is only meaningful under the same precondition. Any narrower or wider list would make SHIP disagree with REVIEW about whether comparison material exists.
2. **Duplicate the list and hold it with a test, rather than reference it.** The hook's jq filter reads `.artifacts` inline from the entry, and the config format has no way to point at another entry's list. Adding a reference mechanism would be a hook change for one entry. `tests/test-ship-drift-gate.sh` (G1) asserts the two lists are equal in each config, with a floor so two missing lists cannot pass as "equal".
3. **Configuration only.** The hook already gates SEQUENCE entries; no code changes.

## Decided NOT to change

- **`runtime-validation`'s SHIP fallback.** It also covers API and CLI checks. A gate keyed on frontend tooling would hide those, so there is no single precondition to gate it on.
- **The phase-map lines.** They describe the flow, not a step to run now.
- **The AUTONOMY CHECK and EVAL STRATEGY hints.** The canonical `pdlc-safety` spec ("eval-strategy classification at DESIGN") requires EVAL STRATEGY to be an always-on DESIGN hint. For AUTONOMY CHECK, the open change `autonomy-control-coherence` (`specs/pdlc-safety/spec.md`, "Autonomy↔Control Coherence Guidance at DESIGN") requires the guidance to be "model-assessed from the actual design (not keyword-triggered)". An artifact-presence gate is a deterministic file-presence test, so it would decide whether the guidance appears without the model assessing the design. Gating either hint would contradict those requirements.

## Risks

- **The two lists can still diverge if someone edits one by hand.** G1 fails on any difference, in either config.
- **Injection budget.** The measured SHIP shape runs against this repository, which has comparison material, so its bytes do not move. Repos without comparison material get a shorter SHIP block, which is the point.
