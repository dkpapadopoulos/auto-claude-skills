# Setup

Configure auto-claude-skills: install recommended companion plugins, enable agent teams, and download external skills.

## Instructions

### 0. Recommended plugins and MCPs

**Ask the user:** "Would you like to install recommended companion plugins? These provide 15+ additional skills and MCP integrations that the routing engine discovers automatically."

Present the following plugins. For each one, check if it's already installed by looking for its directory in `~/.claude/plugins/cache/`. Skip any that are already present.

**Marketplaces** (needed first):
```bash
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add obra/superpowers-marketplace
```

**Core plugins (essential for SDLC loop):**
| Plugin | Source | What it adds |
|--------|--------|-------------|
| superpowers | superpowers-marketplace | brainstorming, TDD, debugging, planning, code review, and more |
| frontend-design | claude-plugins-official | High-quality frontend interface design |
| claude-md-management | claude-plugins-official | CLAUDE.md auditing and maintenance |
| claude-code-setup | claude-plugins-official | Claude Code automation recommendations |
| pr-review-toolkit | claude-plugins-official | Structured PR review with specialist agents |

**MCP plugins (SDLC data sources):**
| Plugin | Source | What it adds |
|--------|--------|-------------|
| context7 | claude-plugins-official | Up-to-date library/framework documentation via MCP |
| github | claude-plugins-official | GitHub repository management, PR creation, issue tracking via MCP |

Note: Atlassian (Jira/Confluence) is available as a claude.ai managed integration — connect it via `/mcp` in Claude Code. No marketplace install needed.

**Phase enhancer plugins (improve specific phases):**
| Plugin | Source | Phase | What it adds |
|--------|--------|-------|-------------|
| commit-commands | claude-plugins-official | SHIP | Structured commit workflows and branch-to-PR automation |
| security-guidance | claude-plugins-official | IMPLEMENT | Write-time security guard (passive hook) |
| feature-dev | claude-plugins-official | DESIGN | Parallel exploration and architecture agents |
| hookify | claude-plugins-official | DESIGN | Custom behavior rule authoring |
| skill-creator | claude-plugins-official | DESIGN | Skill eval/improvement with benchmarking |
| `<language>-lsp` family | claude-plugins-official | IMPLEMENT, DEBUG, REVIEW | Per-language LSP plugins (e.g. `typescript-lsp`, `pyright-lsp`, `gopls-lsp`, `rust-analyzer-lsp`, `jdtls-lsp`, `clangd-lsp`, `csharp-lsp`, `kotlin-lsp`, `lua-lsp`, `php-lsp`, `ruby-lsp`, `swift-lsp`). **Requires two steps:** (1) install the plugin for your stack, AND (2) install the backing language-server binary declared in the plugin's `plugin.json` `lspServers.<name>.command`. Each plugin's README has the install command for its server (e.g. `npm install -g typescript-language-server` for `typescript-lsp`, `go install golang.org/x/tools/gopls@latest` for `gopls-lsp`, etc.). auto-claude-skills sets `lsp=true` only when both the plugin and at least one declared binary are present. Complementary to Serena (LSP for type/compile errors, Serena for symbol nav and edits). |

For each plugin the user wants, run:
```bash
claude plugin install <plugin-name>@<marketplace>
```

If the user declines, skip this step entirely.

### 1. Agent Teams (recommended)

This plugin includes skills that use collaborative agent teams (agent-team-execution, agent-team-review, design-debate). These require the experimental agent teams feature to be enabled.

**Ask the user:** "Would you like to enable collaborative agent teams? This sets `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in your Claude Code settings. Agent teams allow multiple specialist agents to work in parallel on complex tasks."

If the user agrees, add the environment variable to `~/.claude/settings.json`:

```bash
# Read current settings, add the env var, write back
jq '.env["CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"] = "1"' ~/.claude/settings.json > ~/.claude/settings.json.tmp && mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

If the setting already exists, skip this step and inform the user it's already enabled.

### 2. Cozempic (context protection)

```bash
pip install cozempic
cozempic init
```

If pip is not available, skip this step. Cozempic provides optional context protection for long sessions and agent team workflows.

### 3. Anthropic skills (doc-coauthoring, webapp-testing)

Clone the Anthropic skills repo once and copy both skills:

```bash
git clone --depth 1 https://github.com/anthropics/skills.git /tmp/anthropic-skills
cp -r /tmp/anthropic-skills/skills/doc-coauthoring ~/.claude/skills/doc-coauthoring
cp -r /tmp/anthropic-skills/skills/webapp-testing ~/.claude/skills/webapp-testing
rm -rf /tmp/anthropic-skills
```

### 4. security-scanner (built-in)

The `security-scanner` skill is now bundled with auto-claude-skills. No external installation needed.

If you have the old matteocervelli version at `~/.claude/skills/security-scanner/`, remove it:
```bash
rm -rf ~/.claude/skills/security-scanner
```

For best results, install the CLI tools the skill orchestrates. Check which are missing:

```bash
command -v opengrep && echo "opengrep: installed" || echo "opengrep: MISSING"
command -v semgrep && echo "semgrep: installed" || echo "semgrep: MISSING"
command -v trivy && echo "trivy: installed" || echo "trivy: MISSING"
command -v gitleaks && echo "gitleaks: installed" || echo "gitleaks: MISSING"
```

The security-scanner skill prefers `opengrep` and falls back to `semgrep` — only one SAST binary needs to be installed. Skip the SAST install step if either is already present.

For each missing tool, **ask the user:** "The security-scanner skill works best with [tool]. Would you like to install it?"

If the user agrees, install and initialize each missing tool:

**SAST (Opengrep preferred, Semgrep as fallback)** — code vulnerability scanning. Install one of the two:

Opengrep (recommended — LGPL 2.1 fork, signed binary, no Python dependency, returns real fingerprint/lines fields that Semgrep gates behind a login):
```bash
curl -fsSL https://raw.githubusercontent.com/opengrep/opengrep/main/install.sh | bash
```
Then verify and warm the registry (~30s):
```bash
opengrep --version && opengrep scan --config auto --test . 2>/dev/null; echo "Opengrep ready"
```

Or Semgrep (fallback):
```bash
brew install semgrep
```
Then download rules (~30s):
```bash
semgrep --version && semgrep scan --config auto --test . 2>/dev/null; echo "Semgrep ready"
```

**Trivy** (dependency CVE scanning):
```bash
brew install trivy
```
Then download vulnerability database (~60s):
```bash
trivy --version && trivy fs --download-db-only 2>/dev/null && echo "Trivy DB ready"
```

**Gitleaks** (secret detection):
```bash
brew install gitleaks
```
Then verify:
```bash
gitleaks version && echo "Gitleaks ready"
```

If the user declines any tool, note that the corresponding scan type will be unavailable and the skill will skip it gracefully. The SAST binary (Opengrep or Semgrep) is the highest-value tool — recommend it first.

### 5. Prerequisites (uv package manager)

Serena and Forgetful Memory require the `uv` package manager (Python package installer).

Check if `uv` is available:
```bash
command -v uv || command -v "$HOME/.local/bin/uv" || command -v "$HOME/.cargo/bin/uv"
```

If not found, **ask the user:** "Serena and Forgetful Memory require the `uv` package manager. Would you like to install it? (`curl -LsSf https://astral.sh/uv/install.sh | sh`)"

If the user agrees:
```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
```

After installation, verify with `uv --version` (may need to add `~/.local/bin` to PATH for the current session).

If the user declines, note that Serena and Forgetful Memory will be unavailable and proceed to Step 6.

### 6. Context Stack tools

These tools enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation.

Note: Context7 is already installed via Step 0 (marketplace plugin) and is not duplicated here.

**Detection:** Before presenting the table, check which tools are already installed:
- `chub`: `command -v chub`
- `openspec`: `command -v openspec`
- `serena`: run `claude mcp list` and check for a `serena` entry
- `forgetful`: run `claude mcp list` and check for a `forgetful` entry

Check `npm` availability. If `npm` is missing, note that chub and OpenSpec can't be installed.

Present only the missing tools. If none are missing, skip this step.

**Ask the user:** "Would you like to install the Context Stack tools? These enhance context retrieval with library docs, code navigation, persistent memory, and post-execution documentation."

| Tool | Type | Install command | Scope | Prerequisite |
|------|------|----------------|-------|-------------|
| Context Hub CLI (`chub`) | npm global | `npm install -g @aisuite/chub` | Global | npm |
| OpenSpec | npm global | `npm install -g @fission-ai/openspec@latest` | Global | npm |
| Serena | MCP server | See Serena install steps below | Project-scoped | uv |
| Forgetful Memory | MCP server | `claude mcp add forgetful --scope user -- uvx forgetful-ai` | User (global) | uv |

If uv was not installed in Step 5, skip Serena and Forgetful Memory with a note.

**Serena install steps:**

Check for an existing serena MCP registration before adding a duplicate. If Serena is already registered, detect whether it uses the old git-based install: run `claude mcp list` and inspect the serena entry's command — if it contains `uvx --from git+` it is the old install and should be upgraded (see upgrade note below). Alternatively, `command -v serena` returning a path indicates the new PyPI install is already on PATH.

1. Install the Serena binary (one-time):
```bash
uv tool install -p 3.13 serena-agent@latest --prerelease=allow
```

2. Initialize Serena in the project (creates `.serena/project.yml` if missing):
```bash
serena init
```

3. Register the MCP server — choose one:

Per-project (recommended, captures current working directory):
```bash
claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
```

Global (uses working directory at runtime):
```bash
claude mcp add --scope user serena -- serena start-mcp-server --context claude-code --project-from-cwd
```

**Upgrading from the old git-based install:**

If the user already has Serena registered via the old `uvx --from git+https://github.com/oraios/serena` method, upgrade as follows:

```bash
# Remove old MCP registration
claude mcp remove serena

# Install via PyPI (replaces the old git-based approach)
uv tool install -p 3.13 serena-agent@latest --prerelease=allow

# Re-register with new binary
claude mcp add serena -- serena start-mcp-server --context claude-code --project "$(pwd)"
```

To upgrade an existing PyPI-based install to the latest version:
```bash
uv tool upgrade serena-agent --prerelease=allow
```

**Troubleshooting Serena:**

- *Model ignoring Serena tools.* Recent Opus releases occasionally bias toward built-in tools over Serena. Anthropic's recommended workaround is to start Claude with a Serena-aware system prompt:
  ```bash
  claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"
  ```
  This is a one-time per-session flag — not a permanent install — and is only needed if you observe the model preferring Grep/Read over `mcp__serena__` tools.

- *Slow MCP startup or timeout errors.* Set a higher MCP timeout before launching Claude:
  ```bash
  export MCP_TIMEOUT=60000
  ```

**Optional: Serena official hooks (recommended for heavy Serena usage)**

Serena v1.1+ provides its own hooks to reduce agent drift. These are separate from the auto-claude-skills plugin's built-in nudge hook (which is lighter-weight and activates automatically). For users who want deeper Serena integration, **ask the user:** "Serena provides official hooks for session management and enhanced tool reminders. Would you like to add them to your settings?"

If the user agrees, merge the following hook entries into the existing `.claude/settings.json` (project-level). Add to the `PreToolUse` array and `Stop` array respectively — do not replace any existing hook entries:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "serena-hooks remind --client=claude-code"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "serena-hooks cleanup --client=claude-code"
          }
        ]
      }
    ]
  }
}
```

Note: Do NOT add the `serena-hooks activate` SessionStart hook — the auto-claude-skills session-start hook already handles Serena detection and context setup. The `remind` hook fires on every tool call (broader than our built-in Grep-only nudge) and the `cleanup` hook prevents session data leaks.

**Optional: auto-approve hook.** Serena v1.3.0 also ships `serena-hooks auto-approve`, which auto-approves Serena tool calls when Claude Code is in `acceptEdits` or `auto` permission mode. Skips the per-tool approval prompt entirely. **Ask the user:** "Do you want Serena tool calls to be auto-approved when you're in `acceptEdits` or `auto` mode? (Recommended for users who run long autonomous sessions; skip if you prefer to approve each call.)"

If the user agrees, merge this into the `PreToolUse` array of `.claude/settings.json` (alongside the `remind` entry — do not replace it):

```json
{
  "matcher": "mcp__serena__.*",
  "hooks": [
    {
      "type": "command",
      "command": "serena-hooks auto-approve --client=claude-code"
    }
  ]
}
```

After installation, verify MCP servers with `claude mcp list` (look for "Connected" status) and CLIs with `command -v`.

### 7. Incident analysis tools (optional)

These tools enhance the incident-analysis skill. Investigation works without them (Tier 2 gcloud CLI or Tier 3 guidance-only), but installing them unlocks faster queries, autonomous trace correlation, and playbook-driven mitigation.

**Detection:** Before presenting the table, check which tools are already installed:
- `gcloud`: `command -v gcloud`
- `kubectl`: `command -v kubectl`
- GCP Observability MCP: check `~/.claude.json` for a `gcp-observability` entry in `mcpServers`, or run `claude mcp list` and look for it

Present only the missing tools. If all are present, skip this step.

**Ask the user:** "Would you like to configure incident analysis tools? These enable faster log/trace queries and playbook-driven mitigation for production incidents."

| Tool | Purpose | Install | Prerequisite |
|------|---------|---------|-------------|
| `gcloud` CLI | Tier 2 investigation (log queries, traces, error reporting) | `brew install google-cloud-sdk` (macOS) or see [install docs](https://cloud.google.com/sdk/docs/install) | GCP project access |
| GCP Observability MCP | Tier 1 investigation (faster queries, autonomous trace correlation) | Add to `~/.claude.json` mcpServers (see below) | npm, gcloud auth |
| `kubectl` | Playbook execution (rollback, restart, scale) | `brew install kubectl` (macOS) or `gcloud components install kubectl` | Cluster access |

**GCP Observability MCP install:**

Check if `~/.claude.json` already has a `gcp-observability` entry. If not, add it:

```bash
# Read current config, add the MCP server entry, write back
jq '.mcpServers["gcp-observability"] = {"type": "stdio", "command": "npx", "args": ["-y", "@google-cloud/observability-mcp"], "env": {}}' ~/.claude.json > ~/.claude.json.tmp && mv ~/.claude.json.tmp ~/.claude.json
```

The MCP server uses Application Default Credentials. If gcloud is installed but not authenticated, guide through:
```bash
gcloud auth login
gcloud auth application-default login
```

**kubectl** is only needed for v1.3 mitigation playbooks (rollback, restart, scale). Investigation works fully without it. If the user declines, note that playbook execution will be unavailable but investigation and postmortem generation will work normally.

### 8. Multi-user mode (spec-driven + CI gate, optional)

For repos with ≥2 active developers, enable spec-driven mode. Design intent is committed to `openspec/changes/<feature>/` (visible to teammates via `git pull`) instead of gitignored `docs/plans/`. A GitHub Actions workflow validates every active OpenSpec change on every PR.

**Detection:** Check the target repo's state before presenting this step:
- Is `~/.claude/skill-config.json` already set to `{"preset": "spec-driven"}`? If yes, skip preset activation.
- Does `<target-repo>/.github/workflows/openspec-validate.yml` already exist? If yes, skip workflow copy.
- Skip this entire step if both are already in place.

**Ask the user:** "Does this repo have 2+ active developers, or do you want durable design traceability via committed OpenSpec changes? If yes, I'll enable spec-driven mode and install the CI validation gate."

**If yes, execute these actions:**

1. **Set the preset** in `~/.claude/skill-config.json`:
   ```bash
   # Merge the preset into existing config (preserves other fields)
   jq '.preset = "spec-driven"' ~/.claude/skill-config.json > ~/.claude/skill-config.json.tmp \
     && mv ~/.claude/skill-config.json.tmp ~/.claude/skill-config.json
   # If the file doesn't exist yet:
   echo '{"preset":"spec-driven"}' > ~/.claude/skill-config.json
   ```

2. **Copy the CI workflow files** from the plugin's source into the target repo. The plugin source is at `~/.claude/plugins/cache/auto-claude-skills-marketplace/auto-claude-skills/<version>/` or wherever Claude Code installed it — detect via the `CLAUDE_PLUGIN_ROOT` env var or search:
   ```bash
   PLUGIN_SRC="$(find ~/.claude/plugins/cache -name 'auto-claude-skills' -type d -maxdepth 5 | head -1)"
   mkdir -p .github/workflows scripts
   cp "${PLUGIN_SRC}/.github/workflows/openspec-validate.yml" .github/workflows/
   cp "${PLUGIN_SRC}/scripts/validate-active-openspec-changes.sh" scripts/
   chmod +x scripts/validate-active-openspec-changes.sh
   ```

3. **Stage and commit** (do NOT auto-push — the user should review):
   ```bash
   git add .github/workflows/openspec-validate.yml scripts/validate-active-openspec-changes.sh
   git status
   ```
   Tell the user: "Files staged. Review with `git diff --staged`, then commit with a message like `ci: add OpenSpec Validate PR gate`."

4. **Print the manual branch-protection checklist** (the workflow alone doesn't block — GitHub Settings does):
   ```
   Manual step to complete enforcement:
   1. GitHub → Settings → Branches → Branch protection rules
   2. Edit rule for `main` (or Add rule)
   3. Check "Require status checks to pass before merging"
   4. Add "OpenSpec Validate" to the required status checks list
   5. Save

   Full guide: <target-repo>/docs/CI.md (if you copied it) or the plugin's docs/CI.md
   ```

5. **Offer to copy `docs/CI.md`** too so the consumer repo has the full rollout documentation:
   ```bash
   mkdir -p docs
   cp "${PLUGIN_SRC}/docs/CI.md" docs/CI.md
   ```

6. **Optional — migrate existing `docs/plans/*-design.md` artifacts.** If the
   target repo already has in-progress design docs under `docs/plans/` from
   before spec-driven mode was enabled, offer to run the migration script:
   ```bash
   # First: dry-run to preview what would be copied
   bash "${PLUGIN_SRC}/scripts/migrate-docs-plans-to-openspec.sh" --dry-run
   # If the inventory looks right, copy from the plugin into the target repo
   # and apply:
   mkdir -p scripts
   cp "${PLUGIN_SRC}/scripts/migrate-docs-plans-to-openspec.sh" scripts/
   chmod +x scripts/migrate-docs-plans-to-openspec.sh
   bash scripts/migrate-docs-plans-to-openspec.sh --apply
   ```
   The script inventories `docs/plans/*-design.md`, derives a feature slug
   per file, and copies content to `openspec/changes/<slug>/design.md`. It
   never overwrites an existing target and never deletes the source.
   Review the copied files — they may need `proposal.md` and
   `specs/<capability>/spec.md` siblings to be fully valid OpenSpec changes.

   Skip this step for repos that don't have pre-existing `docs/plans/` work
   or where the user prefers to start fresh with spec-driven mode.

If the user declines this step, no changes are made. They can enable it later by re-running `/setup`.

## Execution

Run each step in order. For steps 0 and 1, use AskUserQuestion to get the user's preference before taking action. For steps 2-4, if a skill directory already exists at the target path, skip it. For steps 5, 6, and 8, use AskUserQuestion to get the user's preference before installing, and skip tools that are already installed.

After setup, confirm what was configured:
- Companion plugins: which were installed or skipped
- Agent teams: enabled or skipped
- Cozempic: installed or skipped
- `~/.claude/skills/doc-coauthoring/SKILL.md` exists
- `~/.claude/skills/webapp-testing/SKILL.md` exists
- `security-scanner`: bundled with auto-claude-skills (no external install needed)
- `uv`/`uvx`: available or skipped
- `chub`: available or skipped
- `openspec`: available or skipped
- Serena MCP: connected or skipped
- Forgetful Memory MCP: connected or skipped
- GCP Observability MCP: configured or skipped
- `gcloud`: available or skipped
- `kubectl`: available or skipped
