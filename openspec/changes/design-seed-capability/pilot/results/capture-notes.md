# Capture notes — recorded before judging, not acted on

`scripts/pilot-capture.sh` (frozen, `1d8feccb…`) emulates `prefers-color-scheme` to
produce a light and a dark screenshot per artifact. For **both** artifacts the two PNGs
came out byte-identical (`cmp -s` reports no difference). The reasons differ, and both
are properties of the artifacts rather than faults in the harness:

| artifact | `prefers-color-scheme` | `data-theme` | why the pair is identical |
|---|---|---|---|
| artifact-a | 0 | 0 | declares no dark theme at all |
| artifact-b | 0 | 3 | has a dark theme, gated on a `data-theme` attribute that the frozen capture procedure does not set |

The harness is not at fault: it was verified before launch against a synthetic probe page
using `prefers-color-scheme`, which produced two byte-different PNGs (HASHES.md Step 3).

**The frozen capture parameters were NOT changed in response to this.** Altering the
instrument after seeing what it produced is the post-hoc amendment the pre-registration
exists to prevent, and it would have advantaged exactly one artifact. The design already
rules on this case: "An arm with no dark theme shows what it shows; that is a finding,
not a disqualification."

Consequence for judging, stated so it is not mistaken for a defect in the package: each
artifact is supplied with one rendered appearance rather than two. The judges also
receive the HTML source, so a theme an artifact declares but the capture does not trigger
remains visible to them there.
