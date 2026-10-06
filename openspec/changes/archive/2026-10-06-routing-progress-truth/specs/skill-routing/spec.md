## MODIFIED Requirements

### Requirement: Sticky Composition Emission on Bare Acks

The activation hook MUST sticky-emit the CURRENT chain step when composition state is active and the user's prompt is short (≤ 6 words by whitespace count), so the SDLC chain context remains visible across bare acknowledgment prompts that would otherwise produce no routing output.

The hook MUST treat the composition-state file (`~/.claude/.skill-composition-state-<token>`) as authoritative. The file holds two lists: `.completed`, the steps for which a Skill tool returned, and `.assumed`, the steps the walker infers. `CURRENT = .chain[n]`, where `n` is the number of chain steps present in either list. Sticky emission MUST NOT add to `.completed`, directly or through a later prompt: `.completed` gains a name only from the `PostToolUse ^Skill$` completion hook. What a sticky turn infers MUST be written to `.assumed`.

A step before the current one MUST render `[DONE]` only when it is in `.completed`, and `[DONE?]` otherwise. The last-invoked signal, which is written when a step is displayed, MUST NOT earn `[DONE]`.

#### Scenario: Bare ack during active chain emits CURRENT

- **GIVEN** composition state with `chain=[brainstorming, writing-plans, executing-plans, ...]` and `completed=[brainstorming, writing-plans]`
- **WHEN** the user submits the prompt `yes`
- **THEN** the hook MUST emit `Phase: [IMPLEMENT]`, `Process: executing-plans -> Skill(superpowers:executing-plans)`, and the full composition chain block with `[CURRENT] Step 3: executing-plans`

#### Scenario: Sticky advances as completed grows

- **GIVEN** the canonical 7-step SDLC chain
- **WHEN** `.completed` grows from `[]` to `[A,B,C,D,E,F]` across the lifetime of a session
- **THEN** for each `i` in 0..N-1, a bare ack MUST emit `chain[i]` as the active skill — never re-emitting the previous step

#### Scenario: Bare replies record nothing as completed

- **GIVEN** a prompt has armed the canonical chain and no Skill tool has returned
- **WHEN** six bare replies follow
- **THEN** `.completed` MUST be empty
- **AND** `.assumed` MUST hold the steps the walk has passed
- **AND** the step mandated on each of those prompts MUST be the one mandated before the lists were split
- **AND** every step before the current one MUST render `[DONE?]`

#### Scenario: A confirmed step and an assumed step render differently

- **GIVEN** a Skill tool returned for the first step and the walk has passed the second without a return
- **WHEN** a bare reply is routed
- **THEN** the first step MUST render `[DONE]` and the second `[DONE?]`

#### Scenario: No composition state means no sticky

- **GIVEN** no `~/.claude/.skill-composition-state-<token>` file exists
- **WHEN** the user submits a bare ack
- **THEN** the hook MUST exit through the pre-existing short-prompt or blocklist path with empty output

#### Scenario: Corrupt composition state fails open

- **GIVEN** the composition-state file contains invalid JSON, or a list that is not an array, or a list naming a step that is not in the chain
- **WHEN** any prompt arrives
- **THEN** the sticky function MUST return silently, the hook MUST exit 0, and no crash MUST occur

#### Scenario: Hijack guard prevents over-emission

- **GIVEN** an active composition chain with `CURRENT=writing-plans`
- **WHEN** the user submits `debug the failing test` (matches `systematic-debugging` naturally)
- **THEN** sticky MUST NOT inject `writing-plans` — the natural process match wins

### Requirement: Pure-Cancel Prompts Clear Composition State

The activation hook MUST recognize a small set of unambiguous cancellation prompts and clear the composition-state file when matched. It MUST also remove the last-invoked signal for the session, because that signal is the cancelled task's position: left behind, the next task is credited with every step up to it. The match MUST be anchored to the whole prompt (with optional surrounding whitespace and trailing punctuation) so mixed prompts that contain a cancel word alongside other content do not trigger this path.

Recognized cancellation tokens: `stop`, `cancel`, `abort`, `nevermind`/`never mind`, `forget it`, `scrap that`, `drop it`, `no thanks`, `nope`, `nah`. Trailing punctuation `[ \t!.,?:;]` MUST be tolerated. Leading whitespace MUST be tolerated.

#### Scenario: Pure cancel clears state and suppresses sticky

- **GIVEN** an active composition chain
- **WHEN** the user submits `cancel`, `stop.`, `cancel?`, `stop!`, `  never mind  `, `nope`, or `no thanks`
- **THEN** the composition-state file MUST be deleted and the hook MUST NOT emit `Process: writing-plans` (or any other CURRENT-step sticky line)

#### Scenario: The next task does not inherit the cancelled one's position

- **GIVEN** a chain walked several steps forward, then a pure cancel
- **WHEN** a new prompt arms the same chain and a bare reply follows
- **THEN** the last-invoked signal MUST have been removed by the cancel
- **AND** the steps mandated MUST be the ones a session with no history is given

#### Scenario: Mixed prompt with cancel word routes naturally

- **GIVEN** an active chain with `CURRENT=writing-plans`
- **WHEN** the user submits `never mind, different plan`
- **THEN** the cancel regex MUST NOT match (anchor blocks); composition state MUST persist; routing MUST proceed via natural trigger matching where `plan` matches `writing-plans`

### Requirement: Composition-State-Aware Early-Exit Bypass

The activation hook MUST consult composition state before exiting via the short-prompt gate (`PROMPT < 5 chars`) or the greeting blocklist. When `_comp_active` returns true, both early exits MUST be bypassed so the bare-ack prompt reaches the routing pipeline. `_comp_active` MUST be true exactly when the chain has steps that are in neither `.completed` nor `.assumed`, counted the way sticky emission counts them.

#### Scenario: Short prompt bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `yes` (3 chars, ≤ 5)
- **THEN** the short-prompt early-exit MUST NOT fire; the hook MUST continue to scoring

#### Scenario: Blocklist bypassed when chain alive

- **GIVEN** composition state with a live chain
- **WHEN** the user submits `ok` (in the greeting blocklist)
- **THEN** the blocklist early-exit MUST NOT fire; the hook MUST continue to scoring

#### Scenario: A chain walked to its end is not live

- **GIVEN** a chain every step of which is confirmed or assumed
- **WHEN** the user submits a prompt shorter than five characters, including one that would match a trigger
- **THEN** the short-prompt early-exit MUST fire and nothing is emitted

### Requirement: Composition completed-array monotonicity
The UserPromptSubmit walker's composition-state write MUST NOT remove entries from `.completed` while the chain is unchanged, and MUST NOT add any. When a prior state file exists with a `.chain` equal to the newly built chain, the written `.completed` MUST be the prior on-disk `.completed` projected through the chain (chain order, no duplicates, entries not in the chain dropped), and the written `.assumed` MUST be the union of the walker's computed prefix and the prior on-disk `.assumed`, projected the same way, less every entry of `.completed`. When the newly built chain differs from the prior `.chain`, neither prior list MUST leak into the new state. Missing, unreadable, or malformed prior state MUST degrade to an empty `.completed` and a prefix-only `.assumed` without failing the hook. The computed prefix MUST NOT contain `requesting-code-review` or `verification-before-completion`, so neither list ever holds a gated step the walker inferred.

#### Scenario: Backward re-anchor preserves recorded progress
- **WHEN** the on-disk state records `.completed` through a later chain step and a prompt re-anchors at an earlier step of the same chain (e.g. a "pr"-matching prompt after verification already ran)
- **THEN** the written `.completed` MUST still contain every previously recorded entry
- **AND** the written `.chain` MUST be unchanged
- **AND** `current_index` MUST reflect the new anchor (the write MUST still happen)

#### Scenario: Chain switch resets completed
- **WHEN** the prompt anchors a chain different from the on-disk `.chain`
- **THEN** the written `.completed` MUST NOT contain entries carried over from the old chain
- **AND** the written `.assumed` MUST hold the computed prefix only

#### Scenario: Malformed prior state degrades to prefix-only
- **WHEN** the prior state file is missing, unreadable, or not valid JSON
- **THEN** the walker MUST write an empty `.completed` and the prefix-derived `.assumed`, and exit zero

#### Scenario: A state file written before the lists were split
- **WHEN** the prior state file has no `.assumed` field and the chain is unchanged
- **THEN** the written `.completed` MUST still contain every entry it held
- **AND** the walk MUST continue from the same step
