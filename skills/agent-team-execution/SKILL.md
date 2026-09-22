---
name: agent-team-execution
description: Use when executing implementation plans with 3+ independent, file-disjoint tasks that benefit from parallel specialist agents with shared contracts and reviewer-gated completion
---

# Agent Team Execution

Execute implementation plans using collaborative agent teams. Lead routes coordination through SendMessage, specialists work in parallel on file-disjoint groups, a reviewer gates every task.

**Prerequisite:** A plan at `docs/plans/*.md` with discrete tasks (see writing-plans skill).

## Mode Selection

```dot
digraph mode_selection {
    "Read plan" -> "Count file-disjoint groups";
    "Count file-disjoint groups" -> "< 3 groups?" [label="analyze"];
    "< 3 groups?" -> "subagent-driven-development" [label="yes"];
    "< 3 groups?" -> "Heavy file overlap?" [label="no"];
    "Heavy file overlap?" -> "subagent-driven-development\n(dependency ordering)" [label="yes"];
    "Heavy file overlap?" -> "agent-team-execution" [label="no"];
}
```

## Roles

| Role | Count | Owns | Prompt |
|------|-------|------|--------|
| Lead | 1 | `shared-contracts.md`, TaskList | `./lead-prompt.md` |
| Specialist | 1-N | Assigned files only | `./specialist-prompt.md` |
| Reviewer | 1 | Nothing (read-only) | `./reviewer-prompt.md` |

## Shared Contracts

A single markdown file at workspace root. Specialists read it; only Lead writes it.

**Contains:** Data models/types, API signatures, environment config.
**Template:** `./shared-contracts-template.md`

## Communication

All coordination via SendMessage. No file-based polling or locking. No structured JSON.

- **Contract change:** Specialist requests -> Lead updates file -> Lead notifies affected specialists
- **Completion:** Specialist submits to Reviewer -> Reviewer approves/rejects -> Lead marks done
- **Cross-boundary:** Specialist A requests -> Lead routes to Specialist B -> B confirms -> Lead notifies A
- **Heartbeat:** Specialist signals activity before heavy operations. Lead does not reply.
- **Stall:** Lead pings silent specialist. No response -> reassign.

## Workflow

### Phase 1: Setup (Lead)

1. Read plan, extract tasks with file lists
2. Group tasks into file-disjoint sets
3. Apply mode selection (< 3 groups -> fall back to subagent-driven-development)
4. Create `shared-contracts.md` from `./shared-contracts-template.md`
5. `TeamCreate("{feature-name}-impl")`
6. **Propagate every ruling into the dispatch artifact before spawning.** See
   "Rulings" below — this is the step that makes the rest of the Mini-Spec true.
7. Spawn specialists with synthesized Mini-Specs (see lead-prompt.md)
8. Spawn one reviewer
9. Create TaskList entries, assign to owning specialists

#### Rulings: recorded is step one of two

A ruling that changes a task **not yet dispatched** must be written into the
**dispatch artifact** — the plan entry the Mini-Spec is built from, or
`shared-contracts.md` — in the same turn it is made.

Recording a ruling in a progress ledger, a chat message, or a todo does not
propagate it. The Mini-Spec is synthesized from the plan; nothing carries a
ledger into the plan. An unpropagated ruling **reads as done in the record and
is absent from the run**, which is worse than forgetting it, because the record
is what stops you checking.

Before dispatching a task, the lead does this, in this order:

1. List the rulings made so far that mention that task.
2. Grep **the dispatch text that will actually be sent** for each one.
3. Dispatch only when every one is present in that text.

The check is on the text being sent, not on the record. A ruling that is in the
ledger and not in the brief fails this check, which is the entire point.

**Observed twice in one session** (2026-09-19, `subagent-driven-development`,
the same mechanism). A ruling that a task must gain a step which runs a capture
and fails on identical outputs never reached the brief: the brief that executed
had four steps and no mention of capture. Three parties — implementer, reviewer
and controller — each accepted a test that exits 0 on skip, on the grounds that
the step existed. It existed in the ledger. Separately, a ruling that every path
resolve to the isolated worktree never reached its task, which then read HEAD
from a shared checkout on a different branch, at a different commit, with
another session live in it.

The lesson was written down after the first instance and still not applied to
two rulings sitting three lines above it in the same file. That is why this is a
mechanical check before dispatch and not advice to remember.

A ruling made **after** a task is dispatched follows the existing contract-update
path instead: edit `shared-contracts.md`, then re-announce to the owning
specialist (see Phase 2). That path already exists and is already documented —
what was missing is the one for a task that has not been sent yet, which is the
strictly more common case.

### Phase 2: Execution

Specialists work in parallel per their prompts. Reviewer processes review requests as they arrive. Lead routes messages and maintains shared state.

### Phase 3: Completion

1. All tasks approved by Reviewer
2. Run full test suite (verification-before-completion)
3. Scope conformance check (advisory, branch-level — see lead-prompt.md)
4. Integration review
5. `shutdown_request` to all agents
6. `TeamDelete`
7. Invoke finishing-a-development-branch

## Deadlock Prevention

| Condition | Detection | Resolution |
|-----------|-----------|------------|
| Specialist stall | No messages or heartbeats | Lead pings: "Status check?" |
| Repeated rejection | Same task rejected 3 times | Lead intervenes directly |
| Cross-boundary blocked | Specialist waiting on another | Lead routes and follows up |
| Crashed specialist | No response to Lead ping | Lead reassigns task |

## Red Flags

- **File-based locking** -- assignment is the only ownership mechanism
- **Polling files for status** -- all status flows through SendMessage
- **Specialists self-marking tasks complete** -- only Lead marks complete after Reviewer approval
- **Skipping the Reviewer** -- every task must be reviewed
- **Lead editing specialist-owned files** -- Lead routes requests only
- **Structured JSON messages** -- plain text via SendMessage only

## Example: Contract Evolution and Cross-Boundary Routing

A plan has 3 file-disjoint groups: model-specialist (Group A), service-specialist (Group B), routes-specialist (Group C).

```
[Parallel start]

model-specialist -> Lead:
  "Requesting contract update: Task type needs dueDate: Date | null."

Lead: [validates against plan, edits shared-contracts.md]
Lead -> service-specialist: "Contract updated: Task.dueDate added. Re-read contracts."
Lead -> routes-specialist: "Contract updated: Task.dueDate added. Re-read contracts."

routes-specialist -> Lead:
  "Need TaskService.listByPriority() but it doesn't exist in contracts.
   service-specialist owns src/services/task.ts."

Lead: [adds listByPriority signature to shared-contracts.md]
Lead -> service-specialist:
  "Contract updated: TaskService.listByPriority added.
   routes-specialist needs this method. Implement and confirm."

service-specialist -> Lead: "Done. listByPriority implemented and tested."
Lead -> routes-specialist: "Change made. Proceed."
```

## Integration

| Skill | Relationship |
|-------|-------------|
| writing-plans | Creates the plan this skill executes |
| subagent-driven-development | Sequential fallback for < 3 tasks or coupled tasks |
| test-driven-development | Specialists follow TDD discipline |
| finishing-a-development-branch | Invoked by Lead after completion |
| verification-before-completion | Lead runs full test suite before finalizing |
