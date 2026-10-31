# #412 Q3 fixture manifest (D5, D7)

Frozen with `docs/plans/2026-10-31-frontend-hint-exposure-prereg.md`. Projects are aliased; the alias key is local
and never committed. Commits are in the projects' own private repositories.

## Status at the freeze: Q3 is cannot-check

D5 needs at least two independent named-class fixtures. One was found. Q3 does not run, and the phone-check harness
is not built. A named-class defect the owner reports after the freeze may be added by a dated amendment to this file,
written before any Q3 subject run. That amendment must give the defect's pre-fix and corrected commits, its capture
hashes, a design excerpt written without reference to the defect, and its hit and false-alarm rubric. When the count
reaches two, the harness manifest below is completed and frozen in the same amendment, before any run.

## Search (2026-10-31)

One read-only sweep covered all 441 `*.jsonl` and `*.jsonl.bak` transcripts on this machine. It excluded the 8
consulted sessions, this session and both earlier test fixtures, and looked for owner complaints about a rendered
screen in the three named classes. It found 5 candidates. Notes from the sweep:

- No candidate of the stranded-word class exists outside the excluded sessions.
- Most of the owner's UI feedback is inside the excluded sessions.
- One candidate survived only as `/goal` arguments in a `.bak` copy. A filter that drops text starting with `<`
  hides such prompts.

## Listed

| id | project | class | pre-fix commit | corrected commit | screens (pre / corrected) | capture sha256 (pre / corrected) |
|---|---|---|---|---|---|---|
| F1 | P2 | crowding | `359c339a50e3cc500eb4bb125d6ae1add9c475fe` | `5c4398537b6c955685d2ac132730fd72c2943466` | 67 / 7 | `dbf52d8e9db5096c9c8ec52e608b7b95fdebc497029a6b9790f913d8e675e580` / `464e9c656a02fa1950a30f830ceeae21cc4e2ca855ea9d938512adf47f8d7817` |

**F1 (P2), the course workbook page on a fresh device.**

- Defect: every unit's parts are listed with an empty "Not written yet." field each. The page runs to 67 phone screens.
- Fix: the owner accepted a page grouped by unit, with unwritten parts reduced to links. It runs to 7 screens.
- How it arose: the owner asked for a review of whether the interfaces were "needlessly wordy and complex". This was
  a prompted review, not a defect the owner caught on a screenshot. That is a weaker fixture than the earlier two,
  and is stated before any run.

## Recorded, not listed

| candidate | project | why not listed |
|---|---|---|
| top-bar support button | P5 | Rendered at both commits (`073d7ad0c3d550de260d5198fe55762990c2041c`, `5211222ea274be991996bd7d3d7d02b920500b0f`). The pre-fix 12 px label is legible at its rendered size; the defect was a 32 px tap target, a class the checklist does not name. Usable only as an exploratory unnamed-class fixture, never toward the two. |
| modules about 12 screens long, small text | P5 | The fix is in the repository's first commit, so no pre-fix commit exists. |
| durations given to the minute | P2 | Unnamed class (content precision), not a rendering defect. |
| exercise demo link not visible | P4 | The cause was a stale bundle, not the layout. Needs a simulator. |

## Capture spec (shared by every fixture)

- Build: `git archive <commit> | tar -x` into an empty directory, so the repository is never touched.
- Serve: `python3 -m http.server --bind 127.0.0.1`.
- Viewport: Playwright Chromium (headless), 390 × 844 at device scale 2. Load with `waitUntil: 'networkidle'`, then
  wait 800 ms.
- Screens: scroll in steps of 684 px (160 px overlap) until the bottom, taking one viewport screenshot per step.
- The capture hash is the sha256 of the screenshots concatenated in screen order.
- Capture script sha256: `8a2860c5dee12f7db430f034ad6191011e7e7e4836fed6f4bef6ac4c6113d1db`.

## Harness manifest (D7), to complete by amendment when a second fixture lists

These items are left open, because no subject runs at the freeze:

- model id and CLI version;
- the exact arm prompts;
- the hashes of the hint, `frontend-design` SKILL.md and design excerpts;
- the run-order seed;
- the per-fixture hit and false-alarm rubric.

These are fixed now:

- the arms are control and checklist (the frozen PHONE CHECK text);
- each fixture × state × arm gets 5 runs;
- tools are Read only;
- subjects run in an isolated HOME;
- outputs are scored blind, with arm labels and treatment phrases masked.
