#!/usr/bin/env bash
# RED fixture: the `function` definition form. Bash defines test_delta here
# exactly as it would with `test_delta() {`, so a never-invoked one is a real
# coverage hole — and it is invisible to a matcher that only looks for `()`.
test_alpha() { :; }
test_beta() { :; }
function test_delta_never_invoked { :; }

test_alpha
test_beta
