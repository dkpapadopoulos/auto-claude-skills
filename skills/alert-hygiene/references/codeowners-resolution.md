# alert-hygiene — Stage 1 CODEOWNERS ownership resolution

Read at SKILL.md Stage 1 before ownership resolution via CODEOWNERS (after IaC module discovery). Its rules (two-layer resolution, artifacts, owner priority, report integration) stay in SKILL.md. Moved verbatim from SKILL.md.

**Flow:**

```bash
# Fetch CODEOWNERS (single gh api call)
gh api "repos/$REPO/contents/CODEOWNERS" --jq '.content' 2>/dev/null \
  | base64 -d > "$IAC_DIR/CODEOWNERS" 2>/dev/null
```

Then in Python:

```python
# Parse CODEOWNERS rules
codeowner_rules = []  # [(glob_pattern, [owners])]
for line in open(f'{iac_dir}/CODEOWNERS'):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    parts = line.split()
    codeowner_rules.append((parts[0], [p for p in parts[1:] if p.startswith('@')]))

def resolve_owner(filepath):
    """Last matching CODEOWNERS rule wins (git spec)."""
    matched = None
    for pattern, owners in codeowner_rules:
        # Convert CODEOWNERS glob to simple match
        if fnmatch.fnmatch(filepath, pattern) or filepath.startswith(pattern.rstrip('*')):
            matched = owners
    return matched

# For each entry in iac-modules.json:
# 1. Check if file is in tf/squads/{squad}/ → squad name is the owner
# 2. Else resolve via CODEOWNERS match on the file path
# 3. Store as 'suggested_owner' in the mapping
```
