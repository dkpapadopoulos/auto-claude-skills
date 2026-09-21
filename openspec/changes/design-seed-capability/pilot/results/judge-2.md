# Judge call 2 — order REVERSED (B then A)

Model: codex (OpenAI), via scripts/consult-dispatch.sh, read-only isolated dir.
Package digest: 9a0ad81a21313f37177d1cf4dcbccc8858d3c5e2561c51956fecde39f0df9d9d
Sent: 2026-09-21T08:02:28Z
Presentation order: FIRST = artifact-b, SECOND = artifact-a

---

**FIRST artifact — 25/32**

| Dimension | Score | Specific evidence |
|---|---:|---|
| R1 — Precision | **2** | Declares fixed precision per column and suppresses floating-point tails in the main display. However, shares use **0 decimals**, and order values, fees and cash use **2**, rather than the rubric’s **8 for quantities and 4 for money**. Only limit prices use 4. Hover titles expose unrounded source values. |
| R2 — Identifier fallback | **4** | Both missing-ticker rows visibly include usable identifiers: `inst-aggs` and `inst-puls`. Although a dash occupies the ticker line, the instrument cell itself remains identified. |
| R3 — No invention or inference | **2** | Preserves supplied order figures and leaves absent cash balances, FX rates and current metrics missing. But it labels portfolio total value **CHF**, although `portfolio_state` supplies no currency. It also converts recorded review-gate breaches into definitive **“Blocked” / “Gate blocked”** execution states and prescribes a clearance workflow absent from the envelope. |
| R4 — Visual hierarchy | **3** | The prominent top banner immediately directs attention to the two breaches and **98.8% exposure**. Orders follow directly. However, the consequential exposure number has ordinary bullet-text emphasis; the banner heading dominates rather than the figure itself. |
| R5 — Financial readability | **4** | Right-aligned, monospaced, tabular numbers; grouped thousands; separate low/high limit columns; explicit currency/unit headers; and aligned current/post-trade/delta columns make the five orders easy to compare. Row separators and a distinct totals strip support scanning. |
| R6 — Repeated elements and states | **3** | Order rows, missing-value dashes, status pills and cards are consistent. Warning and breach pills retain their treatments in action items. One weakness: empty snapshot drift receives the same green success treatment as no policy violations, although an empty drift collection does not establish a successful check. |
| R7 — Empty and absent sections | **4** | Explicitly labels policy violations, snapshot drift, findings and statement IDs **“present, empty.”** Separately labels **integrity evidence** and **comparators** **“absent.”** This satisfies both explicit-empty handling and the top-score absent-section criterion. |
| R8 — Value fidelity | **3** | Embedded JSON matches the supplied envelope. Displayed order quantities, limits, fees, weights and metrics trace to it with rounding—for example, **563** shares and **59.1498–59.4463** limits. Fidelity is weakened by the unsupported CHF designation for total portfolio value and execution-status assertions. |

**SECOND artifact — 20/32**

| Dimension | Score | Specific evidence |
|---|---:|---|
| R1 — Precision | **2** | Formatting consistently removes floating-point tails, but shares use **0 decimals**, money generally **2**, and limit prices **4**. This does not implement the required 8/4 quantity/money policy, and no reader-facing precision policy is declared. |
| R2 — Identifier fallback | **4** | The two affected symbol cells show **“no symbol”** followed by `inst-aggs` or `inst-puls`. Both rows retain usable internal identifiers; neither cell is blank or unidentified. |
| R3 — No invention or inference | **1** | Computes unsupplied midpoint prices, **±25 bps** bands, **1.13636 implied** FX rates and aggregate net cash. It explicitly infers CHF for portfolio total value and a sign-off requirement from gate breaches. Disclosure makes these inferences transparent, but the rubric expressly prohibits them. |
| R4 — Visual hierarchy | **3** | The first red banner foregrounds the review breaches and **98.8% exposure**. However, three similarly prominent banners compete for attention and push orders downward. No consequential numerical figure receives dominant typographic emphasis. |
| R5 — Financial readability | **3** | Right-aligned monospaced values, thousands separators and consistent row rules support comparison. But paired currencies, implied rates, midpoint annotations and classification strings crowd cells. Secondary numbers and notes have visibly low contrast, and narrow action-item panels produce extensive wrapping. |
| R6 — Repeated elements and states | **3** | Buy/sell badges, signed-value colors, flagged rows and panel styling repeat consistently. State treatment is less consistent across sections: warnings and review gates have distinct banners but become identical neutral pills in the action list. |
| R7 — Empty and absent sections | **2** | Shows **“Snapshot drift: empty,” “Statements: none listed,”** and footer **`findings=0`**. However, `banner()` returns immediately for empty arrays, silently dropping **`policy_violations: []`**. It also does not identify absent comparators or integrity evidence. |
| R8 — Value fidelity | **2** | Embedded JSON matches the envelope, and primary order figures and proposed metrics are correctly rounded. Additional displayed figures are calculated rather than supplied. More seriously, **“Net cash after orders +1,329.85 CHF”** is only the sum of order cash deltas: the envelope supplies no opening cash balance, and this sum excludes separately listed fees. It cannot establish post-order cash. |

**Overall:** FIRST scores higher, **25/32 versus 20/32**, using equal weighting. The largest difference is **R7**, where FIRST explicitly distinguishes empty collections from absent sections. FIRST also leads on **R3, R5 and R8**. Both miss the declared numeric precision policy, and both preserve usable internal identifiers.

**Render viewing and provenance:** I viewed both supplied renders: FIRST’s light appearance and SECOND’s dark appearance. I formed no specific impression about their author, model or tool of origin; their styling does not establish provenance.