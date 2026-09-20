#!/bin/bash
# RED fixture — same defect, heredoc form. An UNQUOTED delimiter expands, so the
# backticked word is executed exactly as in the double-quoted case.
cat <<EOF
Run `project-verification` before pushing.
EOF
