# Pre-launch measurements

Every claim in `HASHES.md` v2 about the arm environment rests on these. They were run
before either arm launched. Recorded here because a pre-registration that hashes a
script but not the measurement justifying how that script is invoked has its
evidentiary weight in the wrong place.

Harness: Claude Code 2.1.267, git 2.54.0 (Apple Git-157), macOS darwin 25.6.0.

## M1 — the capability boundary is inert for a subagent, live for a headless session

Same worktree, same hook file, same tool. Only the dispatch mechanism varies.

| dispatch | `CLAUDE_PROJECT_DIR` | `WebFetch https://example.com` |
|---|---|---|
| subagent of the orchestrating session | UNSET (reported by the subagent itself) | **SUCCEEDED** — page fetched, no marker |
| headless `claude -p`, cwd = the worktree | set by the harness | **DENIED** |

The headless refusal, verbatim:

```
pilot-arm-deny: WebFetch is an outbound tool and the pilot arms have no outbound path
— refused by the pilot arm capability boundary
```

The subagent leg additionally reported `WebSearch` SUCCEEDED (9 results). The headless
leg is the pair's **positive control**: it proves hook, settings wiring and worktree are
sound, so the subagent leg succeeding is genuine inertness and not a broken probe.

## M2 — the plugin stack injects the treatment's own instruction into BOTH arms

With the user-level plugin stack loaded, the `auto-claude-skills` `UserPromptSubmit`
hook renders into every arm prompt:

```
- DESIGN SEED: for UI work, adopt the shipped styleguide seed rather than inventing
  tokens — see `assets/design-seed/ADOPT.md` (tokens.css defines ROLE tokens to
  reference, never literals; `checks/token-lint.sh` enforces references) ... If the
  project already has `design/`, read `design/styleguide.md` instead of the seed.
```

That reaches **arm C**, the control. A subagent fires no `UserPromptSubmit`, so this
channel exists only under headless dispatch — the mechanism change created it.

## M3 — disabling the plugins removes it, and the boundary survives

`--settings` with an explicit `false` per plugin (20 of them; an empty
`enabledPlugins: {}` does NOT work — merge semantics leave user settings intact).
`CLAUDE_CONFIG_DIR` isolation was tried first and **rejected: it breaks authentication**
(`Not logged in · Please run /login`).

One probe, four properties at once:

```
WebFetch                    -> DENIED, "pilot-arm-deny: ... refused by the pilot arm
                               capability boundary"          (boundary still live)
CLAUDE.md pointer           -> quoted back verbatim           (treatment delivery intact)
design/styleguide/token
  instruction in context    -> NONE                           (contamination gone)
skills active               -> 22, all Claude Code built-ins, no plugins
```

## M4 — the preamble is unnecessary once the plugins are off

| arm prompt | plugins | skill invocations | first tool calls |
|---|---|---|---|
| brief alone | loaded | `superpowers:brainstorming` x2 | ceremony |
| preamble + brief | loaded | 0 | `Bash` |
| **brief alone** | **disabled** | **0** | **`Bash`** |

The brainstorming invocation was a symptom of the loaded plugin stack, not of the
brief. The preamble is therefore reduced to what the plan already sanctions — worktree
path and budget cap — plus one fact of headless operation (no interactive user can
answer a question). Its exact bytes are `arm-preamble.txt` beside this file, hashed in
`HASHES.md`.

**Caveat, stated rather than papered over:** each row is ONE draw from a stochastic
process. Actual skill invocations per arm are therefore recorded as an *observed*
variable in `arm-consumption.md`, not assumed to be zero.

## M5 — the worktree's SessionStart hooks inject maintainer memory and reach the network

Raised in review as unmeasured. Measured:

```
"Cozempic: guard active"  (SessionStart fired)
+ the full MEMORY.md index from
  ~/.claude/projects/-Users-damian-IdeaProjects-Dion/memory/
  — 13+ pointers, e.g. "Agent push policy in Dion", "Two gates block pushes in Dion"
```

Setting `COZEMPIC_NO_AUTO_INIT` / `NO_GLOBAL_INIT` / `NO_AUTO_UPDATE` / `DISABLE` did
**not** suppress it. The memory index is Claude Code's built-in auto-memory, resolved
from the git common dir (so a worktree of Dion gets Dion's), not a cozempic artifact.

Dion's tracked `.claude/settings.json` additionally registers, besides the deny hook:
`SessionStart` → `cozempic digest inject` and `uv pip install --upgrade cozempic` (**an
outbound network call made before any tool call, outside the PreToolUse boundary**),
plus `PostToolUse` on every tool call. Under subagent dispatch none of this ran per arm.

**Scope, so the severity is not overstated or understated.** No portfolio data reached
the arm: the `private_data` leg concerns the financial store, and Task 8 Step 0's
`*.duckdb` check governs that. What reached it is maintainer engineering notes —
symmetric across arms and unrelated to design, so it biases nothing. But "no private
store exists in the arm worktrees" was an incomplete statement of the arms' exposure,
and the outbound `pip install` contradicts "no outbound path" outright.

**Remedy applied:** each arm worktree's `.claude/settings.json` is reduced to the
PreToolUse deny hook alone for the duration of the run, identically for both arms. The
built-in auto-memory index could not be suppressed without `--bare`, which would also
remove the hooks and `CLAUDE.md` — i.e. the boundary and the treatment. It is therefore
disclosed rather than eliminated.
