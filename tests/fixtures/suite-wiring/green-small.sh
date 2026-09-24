#!/usr/bin/env bash
# GREEN fixture: a legitimately SMALL file. Under the previous hardcoded floor
# of 5 this failed for having no defect at all; six real files are this shape.
test_alpha() { :; }
test_beta() { :; }

test_alpha
test_beta
