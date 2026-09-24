## PR Review: guard changes

### Blocking issues 🚫

- `hooks/openspec-guard.sh:1198` — the new leg runs before the deny and can set
  `_DECISION`, so an advisory can suppress a gate.

---
