# pdlc-closed-loop delta: registered hint cut

## MODIFIED Requirements

### Requirement: Composition Chain Integration
The routing engine MUST wire `product-discovery.precedes = ["brainstorming"]` (DISCOVER → DESIGN) and `outcome-review.precedes = ["product-discovery"]` (LEARN → DISCOVER loop). (The sentence requiring an advisory LEARN reminder hint in the SHIP composition was removed by the registered hint cut; `outcome-review` stays reachable by its triggers.)

#### Scenario: DISCOVER precedes DESIGN
- **WHEN** the composition chain is computed for a DISCOVER-then-DESIGN flow
- **THEN** `product-discovery` appears before `brainstorming` in the chain

#### Scenario: LEARN loop routes back to DISCOVER
- **WHEN** outcome-review fires and the loop reopens
- **THEN** the next-cycle precedence routes through product-discovery
