# Non-human UserPromptSubmit shapes

Inputs that reach `UserPromptSubmit` hooks but were not typed by the user. Used by
`tests/test-activation-nonhuman-skip.sh`.

The WRAPPER text in each file is verbatim from live transcripts (Claude Code 2.1.285, observed
2026-10-04/05): the intro line, the `<agent-message from="…">` block, the two fixed harness
paragraphs that can follow it, and the `<task-notification>` + `<system-reminder>` pairing used
by goal check-ins and background review notices. The BODIES are synthetic and deliberately full
of words the router's triggers match (review, PR, code review, new), chosen so that the text on its
own both routes AND starts a composition chain: a silent, stateless result then means the shape was
recognised, not that the text was unroutable or that the phase happens to write no state.

| File | Shape | Observed |
|---|---|---|
| `peer-subagent-handback.txt` | intro + one agent-message block + the "other Claude session … subagent or teammate" paragraph | 31 of 84 peer inputs |
| `peer-teammate.txt` | intro + one block + the "This came from another Claude session" paragraph | 14 of 84 |
| `peer-bare-block.txt` | exactly one agent-message block | 39 of 84 |
| `notice-with-reminder.txt` | task-notification block(s) followed only by a system-reminder block | 29 of 661 notifications |

Before the skip existed, 80 of the 84 peer inputs and 29 of these 29 notifications received a
routing block with a `MUST INVOKE` line.
