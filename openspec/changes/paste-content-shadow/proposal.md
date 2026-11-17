## Why

Text the user pastes reaches the activation hook inside a harness wrapper and scores as if the user had typed it (#409). Over the owner's transcripts (3,001 distinct prompts, 2026-10-01..11-16), 79 carried a wrapped paste and the current hook gave 73 of them a `MUST INVOKE`. Two blind labellers (Opus 5.5, Sonnet 5.5; 183/199 agreement) judged 56 of the mandates that came only from pasted text WRONG and 2 RIGHT; the 2 right ones were prompts whose typed text only pointed at the paste.

The obvious fix, stripping the paste before scoring, deletes the composition-chain state on 50 of the 79 prompts. The push gate runs its chain checks only when that state exists, so in a session opened by a paste they would never run. That is the bypass shape `routing-suppression-must-be-display-only` records.

Whether hiding paste-only mandates helps is not yet shown on data gathered after the rule was fixed. So this change fixes the rule, adds the means to measure it, and changes nothing anyone sees.

## What Changes

- **A parser** (`hooks/lib/pasted-content.sh`): finds the harness wrapper (an opener with a 4-hex `id`, lazily up to the first closer with the SAME id) and replaces each pair with one newline. An opener without its closer strips nothing, so an unterminated block cannot remove typed text. More than 16 openers: nothing is parsed. A regex failure: nothing is stripped.
- **A shadow record** in `hooks/skill-activation-hook.sh`, written after every print and state write, for each prompt containing the wrapper opener: what rule R (pre-registered, predicate_version 1) would keep and hide. R keeps a selected skill when the hook's own scorer and role caps still select it for the stripped text, or when sticky composition injected it; R never adds or substitutes a skill. Records go to `~/.claude/.paste-shadow.d/`, one new file each, with no prompt text.
- **`ACS_PASTE_SHADOW=off`** (any letter case) disables the record. Anything else is shadow.
- **The selection's tentative phase** is computed by a function both passes call, instead of inline code (no behaviour change).

## Capabilities

### Modified Capabilities

- `skill-routing`: a pasted-content shadow record exists; it changes no display and no routing state, and carries no prompt text.

## Impact

- `hooks/lib/pasted-content.sh` (new), `hooks/skill-activation-hook.sh`.
- `tests/test-pasted-content-lib.sh`, `tests/test-activation-paste-shadow.sh` (new); fixtures under `tests/fixtures/routing-input/pasted-content/` (real bytes from this repository's own work).
- Stage 2 (a trial arm that displays R) is NOT in this change; it depends on the pre-registered read in `docs/plans/2026-11-17-paste-scoring-409-prereg.md`.
