---
type: gotcha
title: The `when` field in composition entries is read by no hook — conditional gating uses `.plugin` or `.gate`, and neither can see a third-party plugin
description: A `when:` condition never runs; a conditional hint renders unconditionally. `.plugin` is the only availability gate, and `_plugin_installed`'s catch-all checks only claude-plugins-official/, so `when: installed` is inexpressible for third-party plugins.
tags: [hooks, composition, skill-routing, jq, config]
source: hooks/skill-activation-hook.sh:1366,1375,1380 + hooks/session-start-hook.sh:1371-1379 (verified 2026-09-09, PR #244)
timestamp: 2026-09-09T00:00:00Z
---

`grep -rn '\.when\|"when"' hooks/*.sh hooks/lib/*.sh` returns **nothing**. The
`when` field is documentation: 44 entries carry one in `config/default-triggers.json`
today and not one is evaluated. Writing `"when": "installed AND codex available
AND change is not lite"` produces a line that renders on **every** prompt in that
phase — no error, no warning.

Two fields do gate, and they are not interchangeable:

- **`.plugin`** — gates on plugin availability, and is the only mechanism a
  `hints` entry has. The hints branch (`skill-activation-hook.sh:1380`) branches
  on `.plugin` or falls through to unconditional output.
- **`.gate`** — an `elif .gate then` arm exists for `parallel` (:1366) and
  `sequence` (:1375) **only**. The hints branch has no such arm, so an
  artifact-conditional hint is not expressible as data at all.

The second half is worse. `.plugin` resolves through `_plugin_installed`
(`session-start-hook.sh:1371`), whose catch-all arm checks exactly one location
(:1379): `~/.claude/plugins/cache/claude-plugins-official/${_name}`. Even
`superpowers` needed a hardcoded second path. So for any plugin outside that
marketplace, `_plugin_installed` is **always false** and `when: installed`
cannot be expressed without editing the hook.

**Why this bites:** it makes a conditional hint a `hooks/` change — the
highest-risk tier, which also arms `routing-governance` and so demands a clean
covering verdict per push. This repo has mis-priced such a hint as "just a JSON
entry in both configs" **twice** (see `openspec/changes/adopt-addy-mechanics/design.md`
D-1, and again in a 2026-09 adoption analysis). Both times the correction was
found only after the estimate had been published.

Nothing currently mis-renders, but by accident rather than design: every
existing non-plugin hint is `"when": "always"`, so no live entry depends on the
dead field.

Before writing any conditional composition entry, decide which real mechanism
carries the condition — or that the condition needs hook code. Relates to
[[composition-step-precondition-rendering]] (the adjacent trap: a per-step
addition appended to `description` is silently truncated) and
[[one-red-test-blocks-every-routing-push]].
