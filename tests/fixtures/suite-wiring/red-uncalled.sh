#!/usr/bin/env bash
# RED fixture for tests/test-suite-wiring.sh.
#
# Shape harvested from the real defect: tests/test-routing.sh defined
# test_no_stderr_without_explain and invoked it nowhere, and the file reported
# "All tests passed". The names below are deliberately in the repo's own
# bare-call idiom so the guard's matcher sees exactly what it sees in a real file.
test_alpha() { :; }
test_beta() { :; }
test_gamma() { :; }
test_delta_never_invoked() { :; }

test_alpha
test_beta
test_gamma
