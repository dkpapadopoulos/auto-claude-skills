# alert-hygiene — Stage 1 IaC module discovery script

Read at SKILL.md Stage 1 before IaC module discovery. Its rules (preconditions, artifacts, display-name matching, the fallback link) stay in SKILL.md. Moved verbatim from SKILL.md.

**Why repo tree walk instead of `gh search code`:**
- Policy IDs are assigned at `terraform apply` time — they do not exist in `.tf` files, so searching for them always returns 0 results
- `gh search code` has a 10 req/min rate limit and frequently hits 403 on private orgs
- `gh api` (used here) has a 5,000 req/hour limit and works reliably on private repos
- The results are deterministic: if a `display_name` matches, the file path is confirmed

**Flow:**

For each repo in `{iac_repos}` that contains a `tf/` directory:

```bash
REPO="${github_org}/${iac_repo}"
IAC_DIR="$WORK_DIR/iac-discovery"
mkdir -p "$IAC_DIR"

# Step 1: List module directories
gh api "repos/$REPO/contents/tf/modules" --jq '.[].name' \
  > "$IAC_DIR/module-names.txt" 2>/dev/null

# Step 2: For each module, fetch the main TF file and extract display_name values
python3 -c "
import subprocess, json, re, os
repo = '$REPO'
iac_dir = '$IAC_DIR'
modules = open(f'{iac_dir}/module-names.txt').read().strip().split('\n')
mapping = {}
for mod in modules:
    # Try common TF file names in the module
    for fname in ['main.tf', 'google_monitoring_alert_policy.tf', f'{mod}.tf']:
        try:
            result = subprocess.run(
                ['gh', 'api', f'repos/{repo}/contents/tf/modules/{mod}/{fname}',
                 '--jq', '.content'],
                capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                continue
            import base64
            content = base64.b64decode(result.stdout.strip()).decode('utf-8')
            # Extract display_name values from TF
            for m in re.finditer(r'display_name\s*=\s*\"([^\"]+)\"', content):
                dn = m.group(1)
                # Skip condition display names (inside conditions {} blocks)
                # Only keep top-level policy display_name
                mapping[dn] = {
                    'repo': repo,
                    'module': mod,
                    'file': f'tf/modules/{mod}/{fname}',
                    'type': 'module_definition'
                }
            break  # Found file, stop trying alternatives
        except Exception:
            continue

# Step 3: Also scan squad directories for module invocations
try:
    result = subprocess.run(
        ['gh', 'api', f'repos/{repo}/contents/tf/squads', '--jq', '.[].name'],
        capture_output=True, text=True, timeout=10)
    squads = result.stdout.strip().split('\n') if result.returncode == 0 else []
except Exception:
    squads = []

for squad in squads:
    try:
        result = subprocess.run(
            ['gh', 'api', f'repos/{repo}/contents/tf/squads/{squad}',
             '--jq', '.[].name'],
            capture_output=True, text=True, timeout=10)
        files = [f for f in result.stdout.strip().split('\n')
                 if f.endswith('.tf')]
    except Exception:
        continue
    for fname in files:
        try:
            result = subprocess.run(
                ['gh', 'api',
                 f'repos/{repo}/contents/tf/squads/{squad}/{fname}',
                 '--jq', '.content'],
                capture_output=True, text=True, timeout=10)
            if result.returncode != 0:
                continue
            content = base64.b64decode(result.stdout.strip()).decode('utf-8')
            for m in re.finditer(r'display_name\s*=\s*\"([^\"]+)\"', content):
                dn = m.group(1)
                mapping[dn] = {
                    'repo': repo,
                    'module': squad,
                    'file': f'tf/squads/{squad}/{fname}',
                    'type': 'squad_definition'
                }
        except Exception:
            continue

# Step 4: Scan root-level .tf files for module invocations
try:
    result = subprocess.run(
        ['gh', 'api', f'repos/{repo}/contents/tf', '--jq', '.[].name'],
        capture_output=True, text=True, timeout=10)
    root_files = [f for f in result.stdout.strip().split('\n')
                  if f.endswith('.tf')]
except Exception:
    root_files = []

for fname in root_files:
    try:
        result = subprocess.run(
            ['gh', 'api', f'repos/{repo}/contents/tf/{fname}',
             '--jq', '.content'],
            capture_output=True, text=True, timeout=10)
        if result.returncode != 0:
            continue
        content = base64.b64decode(result.stdout.strip()).decode('utf-8')
        # Extract module invocations: module \"name\" { source = \"./modules/X\"
        for m in re.finditer(
            r'module\s+\"([^\"]+)\"\s*\{[^}]*source\s*=\s*\"([^\"]+)\"',
            content, re.DOTALL):
            mod_name = m.group(1)
            mod_source = m.group(2)
            # Store invocation location for modules we already know about
            mod_key = mod_source.split('/')[-1] if '/' in mod_source else mod_source
            for dn, info in mapping.items():
                if info['module'] == mod_key:
                    info['invocation_file'] = f'tf/{fname}'
    except Exception:
        continue

with open(f'{iac_dir}/iac-modules.json', 'w') as f:
    json.dump(mapping, f, indent=2)
with open(f'{iac_dir}/iac-status.json', 'w') as f:
    json.dump({'status': 'ok' if mapping else 'empty',
               'count': len(mapping)}, f)
print(f'Discovered {len(mapping)} display_name → file_path mappings')
"
```
