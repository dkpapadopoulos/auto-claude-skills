# Round-3 acceptance: measured once, against the shipped routing

Spent 2026-09-16 against `cases-round3.json`, frozen unmeasured in the
preceding commit. One shot. The predicate was NOT adjusted afterwards on the basis of
which cases failed — that is what spent round 1.

## Result

**Precision 14/15. Recall 5/15.** The routing is safe and frequently silent.

| Category | Correct | Reading |
|---|---|---|
| `vendor_as_subject` | 5/5 | No false dispatch. This is the class that produced BOTH review criticals (`the o3 bucket needs a read replica`), and it is clean on prompts nobody involved had seen. |
| `asks_me` | 5/5 | The direction inversion never routes outbound. |
| `plain_dev` | 4/5 | One false dispatch — see below. |
| `one_model_view` | 3/5 | |
| `several_models` | 2/5 | |
| `models_interact` | **0/5** | |

```
CATEGORY           ID     CONSULTATION SKILLS SELECTED       VERDICT
one_model_view     om-1   second-opinion                     ok
one_model_view     om-2   second-opinion                     ok
one_model_view     om-3   second-opinion                     ok
one_model_view     om-4   none                               MISS
one_model_view     om-5   none                               MISS
several_models     sm-1   panel                              ok
several_models     sm-2   none                               MISS
several_models     sm-3   none                               MISS
several_models     sm-4   panel                              ok
several_models     sm-5   none                               MISS
models_interact    mi-1   none                               MISS
models_interact    mi-2   none                               MISS
models_interact    mi-3   none                               MISS
models_interact    mi-4   none                               MISS
models_interact    mi-5   none                               MISS
vendor_as_subject  vs-1   none                               ok
vendor_as_subject  vs-2   none                               ok
vendor_as_subject  vs-3   none                               ok
vendor_as_subject  vs-4   none                               ok
vendor_as_subject  vs-5   none                               ok
asks_me            am-1   none                               ok
asks_me            am-2   none                               ok
asks_me            am-3   none                               ok
asks_me            am-4   none                               ok
asks_me            am-5   none                               ok
plain_dev          pd-1   panel                              FALSE-DISPATCH
plain_dev          pd-2   design-debate                      ok
plain_dev          pd-3   design-debate                      ok
plain_dev          pd-4   none                               ok
plain_dev          pd-5   design-debate                      ok
```

## The two findings, with their provenance

**pd-1 is a false dispatch, and the defect predates this set.** "the collapsible PANEL on
the settings screen doesn't remember its open state" selects `panel`. Cause: `panel` is a
single-word skill name, so the full-name boost awards +100 for the ordinary English word.
Measured independently earlier in the same session (`the control panel component is
misaligned on mobile` -> panel=116) and deferred at the time. Round 3 confirms the cost is
a false OUTBOUND dispatch, but the finding and its evidence do not come from this set, so
repairing it does not spend round 3.

`brainstorming` and `synthesize` share the property; `synthesize` matters least (it is
composition-only) and `brainstorming` dispatches nothing.

**`models_interact` 0/5 IS from this set, and it is the sharpest result.** `design-debate`
triggers on `trade.?off|debate|compare|weigh|pro.?con|alternative|architecture`. None of
five naturally-phrased interaction requests use any of them: "argue this out", "rebut",
"back and forth", "challenge ... until they converge", "cross examination". C2 asserts the
three consultation methods are distinguishable; the interactive one has close to no recall
for its own intent, so in practice the distinction is between two methods, not three.

Recording it rather than fixing it: widening `design-debate` from these five prompts is
precisely the tuning that spent round 1. It needs a round-4 set, or acceptance that the
trigger is derived from the CONTRACT rather than from these examples.

## What this does and does not license

Licensed: "no false outbound dispatch on 15 unseen ordinary-development and
asks-the-assistant prompts".

NOT licensed: any recall claim. 5/15 is the measurement, and the causes are known
(`design-debate`'s vocabulary, and single-model phrasings like "i'd like o3's take"
that no clause covers).
