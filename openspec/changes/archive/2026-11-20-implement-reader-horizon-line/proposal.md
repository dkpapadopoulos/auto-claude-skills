# The IMPLEMENT reader prints the registered horizon

## Why

Below the floor, `scripts/shadow-adjudicate.sh --status` printed "horizon ~2026-09-08 (pre-registered 2026-07-28)". The re-registration of 2026-08-29 in `openspec/changes/implement-shadow-event/design.md` withdrew that date and committed no new one ("Horizon is therefore unknown, pending re-estimate"), and the amendment of 2026-10-25 repeats it. The readout quoted a deadline the window does not have, and on 2026-11-20 that date read as two months overdue.

## What changes

The row reads "unknown, pending re-estimate (re-registered 2026-08-29; no date is committed)". A test ties it to the design's sentence, so registering a horizon without updating the row fails.

## Not changed

No constant, floor, band or count. The re-estimate the re-registration promised is still owed; it is tracked as an issue, not done here.
