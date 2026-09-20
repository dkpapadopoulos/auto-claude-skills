#!/bin/bash
# GREEN: a here-string. `<<<` must not be re-matched as `<<` on its own 2nd-3rd
# characters — doing so registered a heredoc named "$PAIR" whose terminator never
# arrives, swallowing the rest of the file unscanned (real: skill-activation-hook.sh:1983).
PAIR="1 2 3"
read -r A B C <<< "$PAIR" || true
MSG="see verification-before-completion first"
printf "%s %s %s %s\n" "$A" "$B" "$C" "$MSG"
