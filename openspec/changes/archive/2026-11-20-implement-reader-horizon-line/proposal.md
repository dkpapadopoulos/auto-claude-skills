# The IMPLEMENT reader prints the registered horizon

## Why

Below the floor, `scripts/shadow-adjudicate.sh --status` printed "horizon ~2026-09-08 (pre-registered 2026-07-28)". The re-registration of 2026-08-29 in `openspec/changes/implement-shadow-event/design.md` withdrew that date and committed no new one ("Horizon is therefore unknown, pending re-estimate"), and the amendment of 2026-10-25 repeats it. The readout quoted a deadline the window does not have, and on 2026-11-20 that date read as two months overdue.

## What changes

The row reads "unknown, pending re-estimate (re-registered 2026-08-29; no date is committed)". A test fails when the design's "No new horizon date is committed" sentence is changed or removed. It does not catch a horizon registered in a new section that leaves that sentence in place, which is how this design has been amended so far; #457 lists updating the row as a step of the re-estimate.

## Not changed

No constant, floor, band or count. The re-estimate the re-registration promised is still owed; it is tracked as an issue, not done here.
