# Command Risk Labels — Destructive-Action Annotation

Applied at the HITL gate (see SKILL.md § "1. HITL Gate") before presenting any
destructive or mutating command. Read-only investigation queries are NEVER labeled —
labeling safe reads trains the reader to ignore the marker (alert fatigue; see the
`alert-hygiene` skill).

## Format

Emit one ASCII line immediately before the command:

    RISK: HIGH — <reason>      # irreversible, data-loss, or wide blast radius
    RISK: MEDIUM — <reason>    # temporary disruption or reversible

The leading token `RISK:` MUST be ASCII so it is regex- and `grep -F`-assertable. An
emoji MAY follow the reason for readability but MUST NOT be the sole marker.

## Level selection

| Level | Use for | Examples |
|-------|---------|----------|
| HIGH | Irreversible / data loss / wide blast radius | resource deletion, node drain, cluster destroy, IAM policy change |
| MEDIUM | Temporary disruption / reversible | workload restart, rollout undo, replica or resource resize |

## Examples

    RISK: HIGH — deletes the NetworkPolicy; if wrong, all checkout traffic stays blocked.
    kubectl delete networkpolicy update-checkout-from-frontend

    RISK: MEDIUM — rolling restart drops in-flight connections on this deployment only.
    kubectl rollout restart deployment/frontend
