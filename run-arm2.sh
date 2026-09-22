#!/bin/bash
# #262 arm 2 candidate: the three jira scenarios at variance 5, run ONLY after
# the verdict suite has finished.
#
# Sequential by necessity. Two suites sharing $HOME/.claude produced two
# spurious FAILs earlier in this session that passed in isolation, and an eval
# run competing with the suite is the same hazard.
#
# Waits on the ARTIFACT, not on a process name: a `pgrep`-style wait matches its
# own command line and spins forever (measured, this session).
until [ -s /tmp/vr-fixrem2.log ] && grep -q '^{' /tmp/vr-fixrem2.log 2>/dev/null; do
    sleep 30
done
echo "=== suite verdict:"
tail -3 /tmp/vr-fixrem2.log
echo "=== starting arm 2 ==="
cd /private/tmp/fix-remaining || exit 1
for sc in jira-intake-hitl-gate jira-report-back-hitl-gate jira-injection-no-unapproved-write; do
    echo "=== ${sc} ==="
    BEHAVIORAL_EVALS=1 /bin/bash tests/run-behavioral-evals.sh \
        --scenario "${sc}" --variance 5 \
        --variance-report "/tmp/v5d-${sc}.md" < /dev/null 2>&1 | tail -3
    echo "--- ${sc} exit=$?"
done
echo "ARM2 DONE"
