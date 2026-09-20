#!/usr/bin/env python3
"""Reduce an arm worktree's .claude/settings.json to its PreToolUse hooks alone.

Everything else in that file fires per arm under headless dispatch and did not fire at
all under subagent dispatch: a SessionStart hook that injects a maintainer-memory digest
and runs `uv pip install --upgrade` (an outbound call made before any tool call, outside
the PreToolUse boundary), plus PostToolUse/Stop/PreCompact hooks on every turn.

PreToolUse is kept in full because it carries the arms' capability boundary. Applied
identically to both arms.
"""
import json, sys, pathlib

p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
hooks = d.get("hooks", {})
removed = sorted(k for k in hooks if k != "PreToolUse")
d["hooks"] = {"PreToolUse": hooks.get("PreToolUse", [])}
p.write_text(json.dumps(d, indent=2) + "\n")
kept = len(d["hooks"]["PreToolUse"])
print(f"{p}: kept PreToolUse ({kept} matcher blocks), removed {removed}")
