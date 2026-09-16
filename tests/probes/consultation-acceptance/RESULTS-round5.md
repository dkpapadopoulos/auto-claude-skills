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
