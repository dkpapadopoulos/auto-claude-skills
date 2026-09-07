---
type: convention
title: Genericising shipped text is a two-file change — the spec that demanded the specific version goes stale
description: Removing repo-specific content from a string that ships to every install leaves the spec still requiring it; strict validation passes because it checks structure, not satisfiability, so the stale requirement invites reverting the fix.
tags: [openspec, specs, portability, review, validation]
source: openspec/changes/push-gate-evidence-supply/specs/skill-routing/spec.md
timestamp: 2026-09-07T16:35:00Z
---

When a review says a shipped string is too specific to the authoring repo and you
genericise it, the requirement that mandated the specific version must change in the
same commit. Otherwise the spec keeps demanding precisely what you deleted.

## The measured failure

A composition step's `purpose` text — shipped to every install of the plugin — carried a
runtime measured in the authoring repo, an issue number local to it, and the name of a
gate that only fires in repos of one shape. A review flagged it as wrong for any other
install, and it was genericised.

The spec delta authored alongside it still required that same text to state "the suite's
runtime" and that the suite "is long enough to be backgrounded" — both now deliberately
absent. `openspec validate --strict` **passed**, because validation checks document
structure, not whether a scenario is satisfiable by the implementation. The mismatch was
found only by a re-reviewer reading the spec against the diff.

Left in place, the next person to reconcile code with spec would have restored the
repo-specific text and undone the portability fix, with the spec as justification.

## Why it happens

The spec and the code are usually written in the same session, by the same author, when
the specific figure is *true* — so it does not read as environment-dependent. It only
becomes wrong once the artifact ships somewhere else.

## How to apply

- Treat "make this generic" as touching the artifact **and** its requirement.
- Read the spec for anything asserted as fact about the environment: runtimes,
  measurements, issue numbers, component names that exist only in some repos. A
  measurement from the authoring repo belongs in a design note or comment, never in a
  requirement that ships.
- Do not read a passing strict validation as evidence the spec matches the code.
