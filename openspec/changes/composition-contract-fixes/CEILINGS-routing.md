# Known routing ceilings: frame-dependent false positives

Two prompts from the Codex adversarial review reproduce against the real hook and are
NOT fixed. They are recorded here rather than silently left, because they are the same
class as this repo's documented push-gate ceiling (`bash -c` indirection), not oversights.

| prompt | routes to | why a regex cannot decide it |
|---|---|---|
| `add a test fixture containing "i want gemini to review this patch"` | second-opinion | the request is genuine but **quoted** — it is fixture content, not an instruction |
| `document the gemini second pair of eyes feature` | second-opinion | the phrase is a **product name** under a documentary verb |

## Why these are different from the four that were fixed

The four fixed cases were decidable from the token itself: a vendor inside an identifier
(`gemini.json`, `gemini_thinking_budget`) is not a participant; a vendor next to
"standalone panel" without a source marker is a subject; a definite article before a
single-word skill name marks an existing referent. Each is a local property.

These two are **frame-dependent**. The inner text IS a consultation request; what negates
it is the surrounding frame — quotation, or a documentary verb. A regex evaluated over the
whole prompt has no notion of a frame, so any pattern that catches these also catches the
genuine requests they quote. That is a property of the matcher, not a missing clause.

## What bounds the damage

Routing is not dispatch. Both land on skills whose consent gate now requires an explicit
affirmative go-ahead and states that being routed is NOT consent
(`skills/second-opinion/SKILL.md`), with `hooks/outbound-consent-hook.sh` reporting any
dispatch that happens without one. The user sees a disclosure preview naming the exact
payload before anything leaves the machine. The cost here is a spurious skill suggestion,
not egress.

## If someone fixes this

The mechanism would be a FRAME DETECTOR in the hook — not another trigger clause — that
suppresses consultation routing when the prompt is about writing docs, fixtures or tests
that mention a vendor. These two prompts are its first two test cases; add the genuine
requests they quote as controls, because the failure mode of such a detector is
suppressing a real request that happens to contain a quotation.
