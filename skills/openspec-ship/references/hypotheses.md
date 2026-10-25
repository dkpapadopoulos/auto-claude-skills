# openspec-ship — Step 7a-bis: extract hypotheses into session state

Read at SKILL.md Step 7a-bis when `discovery_path` exists in session state AND the file at that path is readable. Moved verbatim from SKILL.md.

1. Read the `## Hypotheses` section from the discovery artifact
2. Parse each `### H<N>:` entry, extracting:
   - `id` — the hypothesis ID (e.g., "H1")
   - `description` — the prose hypothesis line ("We believe ...")
   - `metric` — from the **Metric:** field
   - `baseline` — from the **Baseline:** field
   - `target` — from the **Target:** field
   - `window` — from the **Window:** field
3. Persist hypotheses and mark the change archived. Source the state helpers from the auto-claude-skills plugin, then call them:

```bash
# Self-contained: re-resolve the token here (see "Resolving the session token")
# — a $TOKEN set in an earlier Bash call is NOT in scope, and an empty token
# makes both helpers below return silently, losing hypotheses and archived_at.
PR='<PLUGIN_ROOT>'
TOKEN="$(. "$PR/hooks/lib/session-token.sh" 2>/dev/null && resolve_own_session_token || cat ~/.claude/.skill-session-token 2>/dev/null)"
. "$PR/hooks/lib/openspec-state.sh"

HYPS='[{"id":"H1","description":"...","metric":"...","baseline":"...","target":"...","window":"..."}]'
openspec_state_set_hypotheses "$TOKEN" "<slug>" "$HYPS"

# Record the ship timestamp so write_learn_baseline captures the real ship time,
# not the stop-hook wall-clock fallback. Call after archival in Step 7b completes,
# or here if archival is already complete.
openspec_state_mark_archived "$TOKEN" "<slug>"
```

If the discovery description contains single-quotes (e.g., "it's faster"), construct the JSON via `jq -n` instead of shell-quoted literals to avoid quoting blow-ups.
