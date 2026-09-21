#!/usr/bin/env bash
# RED fixture: `test_x ()` with a space. Bash defines this exactly as
# `test_x()` does. The first cut of the wiring guard added the `function`
# keyword form on the reasoning that a shape nobody uses today must still not
# open the gap — and did not apply that same reasoning to this sibling case.
test_alpha() { :; }
test_beta() { :; }
test_gamma () { :; }

test_alpha
test_beta
