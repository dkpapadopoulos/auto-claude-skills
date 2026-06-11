## ADDED Requirements

### Requirement: Tolerant design-section heading recognition
The PLAN-phase DESIGN COMPLETENESS check MUST recognize each canonical design section by a tolerant heading match rather than an exact prefix match. A section MUST count as present when the design file contains a line beginning with two or three `#` characters followed by a space whose text contains the section's key words — case-insensitively, with each inter-word join accepting either a space or a hyphen, and with arbitrary prefix or suffix text on the heading line. Headings at h4 or deeper, body-text mentions of the section name, and headings indented with leading whitespace MUST NOT count as present.

#### Scenario: Real-world heading variants recognized
- **WHEN** the design file's three sections use variant headings such as `### Capabilities affected`, `## Out of Scope & Non-Goals`, and `## 🚫 Acceptance Scenarios`
- **THEN** the activation output MUST contain `DESIGN COMPLETENESS: all sections present`
- **AND** the activation output MUST NOT annotate any section with `(missing`

#### Scenario: Variant dimensions hold for every section pattern
- **WHEN** the variant dimensions are rotated across sections (e.g. `## 🚫 Capabilities Affected & Constraints`, `### out of scope`, `## Acceptance-Scenarios`)
- **THEN** the activation output MUST contain `DESIGN COMPLETENESS: all sections present`

#### Scenario: Non-heading mentions do not count
- **WHEN** a section name appears only as an h4 heading (`#### Out-of-Scope`) or in body text while the other two sections use canonical h2 headings
- **THEN** the activation output MUST annotate that section with `(missing`
- **AND** the activation output MUST NOT annotate the two present sections with `(missing`
