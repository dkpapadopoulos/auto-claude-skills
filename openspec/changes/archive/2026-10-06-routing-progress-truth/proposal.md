## Why

The activation hook recorded a chain step as completed because it had displayed it. The step it showed on one prompt was written as the "last-invoked" signal, and the next prompt credited that signal into `.completed`. Six bare "ok" replies recorded DESIGN, PLAN and IMPLEMENT as completed, rendered them `[DONE]`, and listed them as "Completed:" after a compaction, with nothing invoked. The canonical spec already said sticky emission "MUST NOT mutate `.completed`"; the code did it indirectly.

Separately, a cancel removed the composition state and left that signal behind, so the next task inherited the cancelled one's position: a new build order was told to request a code review on its second prompt.

## What Changes

- **Composition state has two lists.** `.completed` gains a name only when the completion hook sees a Skill tool return. What the walker infers (the steps before an anchor, and a step shown on the previous prompt) is written to `.assumed`.
- **The walk position counts both lists**, so which step is mandated on each prompt is unchanged. The check that decides whether a chain is still live counts both lists too.
- **`[DONE]` means a Skill returned.** Every inferred step renders `[DONE?]`. The display signal no longer earns `[DONE]`.
- **A cancel also removes the position signal.**
- **Compaction recovery lists assumed steps separately**, labelled as not invoked.

Not changed: a bare reply still advances the walk; the current step is still a count; a chain switch or an unreadable prior state file still starts both lists again.

## Capabilities

### Modified Capabilities
- `skill-routing`: sticky emission, the cancel path, the early-exit bypass and the walker's monotonic write are restated for two lists.
- `compact-recovery`: the recovery text distinguishes confirmed from assumed steps.

## Impact

`hooks/skill-activation-hook.sh`, `hooks/lib/compact-recovery-render.sh`, `.claude/rules/routing-state.md`; `tests/test-activation-progress-truth.sh`, `tests/test-routing.sh`. No gate reads the inferred names: the push guard reads `.completed` for `requesting-code-review` and `verification-before-completion` only, which the walker never wrote. The sticky-repeat experiment's record version moves to 3, because the cancel fix changes which step is injected after a cancel.
