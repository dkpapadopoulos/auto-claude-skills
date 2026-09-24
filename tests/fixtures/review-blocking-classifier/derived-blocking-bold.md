## PR Review: script changes

**Blocking issues 🚫**

1. `scripts/verify-and-record.sh:96` — `grep -c` returns 1 on no match, which
   aborts the script under `set -e` and leaves no verdict.

**Recommendations 💡**

- None.
