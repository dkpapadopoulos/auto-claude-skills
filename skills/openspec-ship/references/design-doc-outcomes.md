# Design-doc resolution outcomes (Step 7c)

`resolve-design-doc.sh --slug <feature-name>` prints one tab-separated line:

    <outcome>	<source>	<path>	<count>

It reads only; it never writes state and never moves a file. Act on the outcome:

| Outcome | What it means | What to do |
|---|---|---|
| `resolved`, source `state` | The path recorded in session state is readable, or Step 7b just moved it and the path printed is the copy under `docs/plans/archive/`. | Generate the report and append it to the file at the printed path. The archived copy is the historical record. |
| `resolved`, source `openspec` or `docs-plans` | Nothing was recorded; exactly one file matches the change slug by name. | Generate the report, and open it with a line saying the design doc was found by filename, not recorded. Append to the file where it is and do not move it: a filename match is evidence, not proof it is this change's doc. |
| `absent` | Nothing recorded and no file matches. | Tell the user: "No design doc found for <feature-name>; no Divergences report." Then continue shipping. |
| `ambiguous` | Several candidates; they follow the first line, one per line. | Show them, generate nothing, and ask the user which file is the design doc. Do not choose one yourself by date or by any other rule. |
| `stale` | A path was recorded and its file is gone (and it is not under `docs/plans/archive/`). | Show the recorded path, generate nothing, and ask the user which file is the design doc. |
| exit 3, no output line | Could not check: a state file exists and cannot be read, or `jq` is missing. | Say "could not check for a design doc". This is not the same as `absent`. |

## When the doc resolves but is thin

- No **Acceptance Scenarios** section: say "design doc has no acceptance scenarios; divergences compared on capabilities and scope only", and compare on those.
- Neither section: say so and write no report. An empty Divergences section reads as "nothing diverged".

## Why this is a script and not a remembered path

The path used to come only from a state write the model was asked to perform during DESIGN. That request was a per-prompt hint, since removed; when it was shown, 5 of 188 sessions performed the write. This step therefore looks for the doc itself.
