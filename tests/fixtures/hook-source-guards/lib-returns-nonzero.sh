#!/bin/bash
# Paired lib for the #137 fixtures: EXISTS, but fails mid-source.
# This is the case `[ -f "$lib" ]` cannot catch — the file is present, so the
# existence check passes, and the failure happens while sourcing.
_FIXTURE_LIB_PARTIALLY_LOADED=true
return 1
# Never reached: the function the caller needs is therefore NEVER defined,
# which is why `|| true` alone is not a sufficient guard.
fixture_helper() { echo "helper"; }
