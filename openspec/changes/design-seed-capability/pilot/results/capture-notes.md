# Capture notes — recorded before judging

`scripts/pilot-capture.sh` (frozen, `1d8feccb…`) emulates `prefers-color-scheme` and
produces one PNG per mode. Measured after the arms ran: for **both** artifacts the two
PNGs are byte-identical (`cmp -s`). The reasons differ:

| artifact | `prefers-color-scheme` | `data-theme` | why the pair is identical |
|---|---|---|---|
| artifact-a | 0 | 0 | declares no dark theme |
| artifact-b | 0 | 3 | declares a dark theme, gated on a `data-theme` attribute the frozen procedure never sets |

The harness is not at fault: before launch it produced two byte-different PNGs against a
synthetic `prefers-color-scheme` probe.

## What this is, stated without varnish

**Equal capture settings are not equal coverage.** The instrument recognises one
theme-selection mechanism and misses another, so it collapses "no dark theme" and "dark
theme reachable a different way" into the same observation. That is a genuine measurement
limitation, and it is not repaired by anything below.

**The frozen parameters were not changed.** The reason is NOT that a change would benefit
one artifact — a valid correction may have asymmetric effects, and "it would help the
wrong arm" is not an argument. The reasons are that changing the activation procedure
would change the registered measurement, and that the change would have been selected
after inspecting the outputs. Under this file's own amendment rule that makes it v2 and
unpoolable, and it would convert a discovered limitation into a silently repaired one
while keeping the original's confirmatory standing.

**The HTML source does not compensate, and saying otherwise would be self-serving.**
Source can establish that a dark theme is *declared*. It cannot establish that the theme
renders, that its contrast is adequate, or that it is reachable by a user. An attribute
selector is equally consistent with a working feature, unfinished wiring, and dead
styling. The honest statement is: **the capture procedure did not exercise artifact-b's
declared dark appearance**, not that judges received an adequate substitute.

## Consequence for the judging package

Each artifact has exactly **one** distinct rendered appearance. These are two capture
*conditions*, not two independent demonstrations of visual quality, and the package must
not imply otherwise.

The judges are told the neutral, symmetric fact — one distinct appearance per artifact —
and nothing else about it. They are **not** given the table above, nor any explanation of
why either artifact's pair is identical. Such an explanation would be an artifact-specific
rescue narrative, which would both break blinding and hand one artifact an excuse.

## Scope of the limitation

Any claim that this pilot assessed dark-theme quality is unsupported, for either
artifact. That is a permanent gap in this run, not something judging or source inspection
can repair.
