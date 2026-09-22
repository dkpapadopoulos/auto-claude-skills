## PR Review: hook changes

### Summary

Adds a Bash matcher to the nudge hook.

## Blocking issues 🚫

1. `hooks/serena-nudge.sh:41` — the fast-path `case` falls through for an empty
   `tool_name`, so a malformed payload reaches the classifier. Fail-open
   requires `exit 0` here.

## Recommendations 💡

- Nothing further.
