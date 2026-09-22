## PR Review: workflow changes

### Blocking issues 🚫

- The `review` job grants `id-token: write` with no justification comment, and
  this workflow uses OAuth rather than OIDC, so the permission is unnecessary
  and the checklist requires it be removed or justified.

---
