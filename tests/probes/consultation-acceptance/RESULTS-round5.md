# Round 5 acceptance — measured 2026-09-16

Set: `cases-round5.json`, sha256 `1b7ed58b4460309f5e570a9bcdeac6bd1580e033af449b4063588ca71e557b4b`
(hashed before measuring, verified identical after commit). Raw: `RESULTS-round5.txt`.
48 prompts, 6 per contract; 4 of 6 vendor-free in each of the three contracts whose
routing the relaxation introduced.

## Result

| | score |
|---|---|
| Precision — no false dispatch on 18 non-consultation prompts | **18/18** |
| Recall — full set | **13/30 (43%)** |
| Recall — excluding the author's flagged suspect-easy cases | **9/22 (40%)** |

Per contract: second_opinion 3/6, answer_critique 4/6, standalone_panel 2/6,
models_interact 3/6, synthesized_plan 1/6.

## This is why the round-4 re-measurement was labelled worthless

After the relaxation, re-running the SPENT round-4 set gave 25/25. The clauses had been
built against those prompts. On prompts nobody had built against, the same code scores
**~40%**. That gap — 100% fitted vs 40% measured — is the entire argument for authoring
a fresh set rather than re-quoting a tuned one.

## The contamination was declared, and it was real but small

`round5-provenance.txt` discloses that the auto-injected memory index leaked that `merge`
is a live routing hazard, and that the skill listing paraphrases two contracts. The author
named the prompts it thought were affected and predicted the bias would make panel/
synthesize cells EASIER. Measured: those 8 flagged cells passed 4/8 and inflated recall by
~3 points. The prediction was correct in direction and modest in size. The 18 negative
prompts were declared unaffected, so **precision is the trustworthy half** of this result.

## One MIS-ROUTE, which was a regression, not a miss

`sp-5` — "put this to codex and gemini separately and show me what each one says" —
routed to `second-opinion`, the ONE-model skill, for a request naming TWO vendors. Cause:
`819c5b5` added `put|paste|send|take|give|hand` to second-opinion for its own recall fix,
while panel's two-vendor clause still listed only `ask|consult|poll|get|run`. The user
would have got one model where they asked for several — a contract violation, and worse
than a silent miss. Verb sets are now aligned and the rule is pinned in panel's fixture:
**two named vendors means panel, whatever the verb.**

## Status of this set

SPENT. Its failure list was inspected to diagnose the mis-route. The other 17 misses were
NOT tuned against — they stand as the honest recall figure. A round 6 would need fresh
authorship, and to be worth more than this one it should be authored in a session without
the memory index injected.

## What ~40% recall means

Vendor-free consultation phrasing routes roughly two times in five. The remaining misses
are paraphrases whose only signals are ordinary English. Whether that is good enough is
the same product question as before, now with a real number attached instead of a
fitted one.

---

## Structural clause work (2026-09-16, after the first round-5 measurement)

10 of the 17 misses NAMED a vendor, i.e. were fixable with no loosening on ordinary
English. That work is done. `RESULTS-round5-after-structural.txt`:

| | before | after |
|---|---|---|
| recall | 13/30 | **21/30** |
| precision | 18/18 | **18/18** |
| new false positives across the 206-prompt accumulated negative corpus | — | **0** |

### What made this different from the four widenings that went wrong

The gate was built BEFORE the change. All 206 accumulated negatives — MLOps, legal,
finance, HR, scientific, econometric, UI, robotics prose, plus every non-consultation
prompt from rounds 4 and 5 — were scanned through the REAL hook first, establishing that
exactly 8 fire and that all 8 are correct cross-skill routings (a decoy borrowed into
panel's fixture is legitimately second-opinion's true positive). After the change: still
exactly 8, none new. Every earlier failure in this branch came from having no such control.

One shared primitive was used instead of ten bespoke patterns: **two named vendors in one
breath, plus a per-skill cue** (panel: same-prompt/raw/labelled; design-debate: an
interaction verb; synthesize: independence AND a combining verb). The cue is what
separates the three contracts; the two-vendor signal is what makes it safe.

### The 21/30 is DEVELOPMENT DATA

Round 5's failure list was tuned against, so this set is now doubly spent. The numbers
worth trusting are the ones NOT tuned toward: precision held at 18/18, and the 206-corpus
scan showed zero regression. A round 6 is required for a real recall figure.

### What this changes about the product question

Vendor-NAMED phrasing — "ask codex and gemini", "gpt-5's take on this" — is now well
covered, and it cost nothing in precision because naming a vendor was always the safe
signal. The open question narrows to vendor-FREE paraphrase, where the trade-off against
ordinary professional language is real.
