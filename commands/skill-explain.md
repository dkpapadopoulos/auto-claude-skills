# Skill Explain

Show how the routing engine scores and selects skills for a given prompt.

**Arguments (optional):** A test prompt in quotes, e.g. `/skill-explain "debug this login bug"`

## Instructions

### 1. Determine the prompt

If the user provided an argument (text after `/skill-explain`), use that as the test prompt.

If no argument was provided, ask: "What prompt would you like to test? (Type any prompt to see how the routing engine would score and select skills for it.)"

### 2. Run the routing hook with SKILL_EXPLAIN=1

Execute the hook with the test prompt piped via stdin, capturing both stdout and stderr:

```bash
output=$(jq -n --arg p "<THE_PROMPT>" '{"prompt":$p}' | \
  CLAUDE_PLUGIN_ROOT='<PLUGIN_ROOT>' \
  SKILL_EXPLAIN=1 \
  bash '<PLUGIN_ROOT>/hooks/skill-activation-hook.sh' 2>&1)
```

Where `<PLUGIN_ROOT>` is the auto-claude-skills plugin directory. Find it by searching for the hook:
```bash
find ~/.claude/plugins/cache -name "skill-activation-hook.sh" -path "*/auto-claude-skills/*" 2>/dev/null | head -1 | xargs dirname | xargs dirname
```

If the plugin root can't be found, check the current working directory for `hooks/skill-activation-hook.sh`.

### 3. Parse and display

The output will contain both:
- **stderr lines** prefixed with `[skill-hook]` — the explain output
- **stdout** — the JSON hook output

Extract the explain lines (those starting with `[skill-hook]`) and display them in a formatted code block.

Also extract the `additionalContext` from the JSON output to show what would actually be injected into Claude's context.

### 4. Present the results

Format the output as:

```
## Routing Explanation

### Prompt
> "{the prompt}"

### Scoring
{scoring lines from explain output}

### Selection
{role-cap selection lines from explain output}

### Result
{result line from explain output}

### Context That Would Be Injected
{additionalContext from JSON, displayed in a code block}

### Session State
- Depth counter: {current value from ~/.claude/.skill-prompt-count-* or "not set"}
- Verbosity level: {full/compact/minimal based on counter}
- Registry: {path to active registry file}

### Zero-Match Diagnostics
- Zero-match count: {read from ~/.claude/.skill-zero-match-count or "0"}
- Total prompts: {read from ~/.claude/.skill-prompt-count-* files, sum all values}
- Zero-match rate: {zero-match / total if both > 0, else "n/a"}
- Recent unmatched prompts (last 10):
  {read last 10 lines from ~/.claude/.skill-zero-match-log, display in a code block}
  If the file doesn't exist or is empty, say "(no zero-match log found — prompts are matching well)"
```

### 5. Offer follow-up

After showing results, say: "You can test another prompt with `/skill-explain \"your prompt here\"`."
