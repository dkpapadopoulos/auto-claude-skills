#!/usr/bin/env bash
# RED fixture: the other direction. bash prints `command not found`, the file
# keeps going, and print_summary still reports success with exit 0.
test_alpha() { :; }
test_beta() { :; }

test_alpha
test_beta
test_never_defined
