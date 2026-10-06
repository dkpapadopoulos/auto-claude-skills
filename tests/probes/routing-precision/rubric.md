# Labelling rubric — sticky-repeat screen (#333, stage A)

Frozen with the pre-registration. Do not edit after the freeze commit; a change is a new
experiment.

You are shown one row at a time. Each row is a moment in a real working session between a
user and a coding assistant:

- `prompt` — what the user just typed.
- `previous_assistant_message_tail` — the end of what the assistant said just before.
- `earlier_prompts` — what the user typed earlier in the session, oldest first.
- `tools_used_since_the_previous_prompt` — what the assistant did in its last turn.
- `process_skills_already_invoked_this_session` — process steps the assistant has already
  carried out.
- `skill` — one process skill.

## The question

> At this turn — given the task in progress, what the user just said, the work already
> done, and what is still outstanding — is REQUIRING the assistant to invoke this specific
> process skill NOW warranted?

Answer with exactly one label.

- **WARRANTED** — yes. The session is at the point where this step is the right next thing,
  or the user has just asked for it or approved moving on to it. A bare "yes", "go" or
  "ok" CAN be warranted: if it approves the step, or the step is plainly what is
  outstanding, say WARRANTED. Do not judge from how short the prompt is.
- **NOT_WARRANTED** — no. The prompt is a reply, a thanks, a question, a correction or an
  instruction about something else; or the step has already been done; or a different step
  is what is outstanding; or the user has said to do something that makes this step
  pointless now.
- **INSUFFICIENT_CONTEXT** — what you were shown does not let you tell. Use this rather
  than guessing. It is not a polite form of NOT_WARRANTED.

## Rules

1. Judge the OBLIGATION, not the wording. The skill may be warranted because of something
   said several prompts ago.
2. Judge THIS skill. If a different process skill is the right next step, the answer for
   this one is NOT_WARRANTED.
3. "Already invoked this session" is evidence, not an answer: a review done before a large
   change may be warranted again after it.
4. You are not told how the skill came to be required, whether the session had been told
   before, or what happened afterwards. Do not try to infer any of that.
5. Give one short reason (twenty words at most).

## Output

One JSON object per row, on its own line:

    {"row_id": "<row_id>", "label": "WARRANTED" | "NOT_WARRANTED" | "INSUFFICIENT_CONTEXT", "reason": "<short>"}
