# Design-doc resolution outcomes (Step 7c)

Step 3 ran `resolve-design-doc.sh --slug <feature-name>` **before anything was created or moved** and kept its output, one tab-separated line:

    <outcome>	<source>	<path>	<count>

The script reads only; it never writes state and never moves a file. It was run first because Step 3 can create `openspec/changes/<feature-name>/design.md`, Step 6 moves that folder into `openspec/changes/archive/`, and Step 7b moves recorded docs into `docs/plans/archive/`. Run at Step 7c it would report a doc that was there a moment ago as `absent` or `stale`, or find the as-built `design.md` this session just wrote. Do not run it again here; use what Step 3 kept.

## Where the doc is now

The path Step 3 kept is where the doc **was**. By Step 7c it may have moved:

| Source Step 3 printed | Where the doc is at Step 7c |
|---|---|
| `state` | `docs/plans/archive/<same filename>`, if Step 7b moved it (it moves every recorded path that existed). Otherwise where it was. |
| `openspec` | `openspec/changes/archive/YYYY-MM-DD-<feature-name>/design.md`, the folder Step 6 archived. |
| `docs-plans` | Where it was. Step 7b moves only recorded paths, and this one was not recorded. |

If the file is not at the place this table gives, say so and write no report. Do not go looking for another file with the same name.

## What to do for each outcome

| Outcome | What it means | What to do |
|---|---|---|
| `resolved`, source `state` | The path recorded in session state was readable. | Generate the report and append it to the doc at its current place. The archived copy is the historical record. |
| `resolved`, source `openspec` | Nothing was recorded; the change folder had a `design.md` before this ship began. | Generate the report. Begin the Divergences section with a line saying the design doc was found in the change folder, not recorded in session state. Append to the archived `design.md`. |
| `resolved`, source `docs-plans` | Nothing was recorded; exactly one file matched the change slug by name. | Generate the report. Begin the Divergences section with a line saying the design doc was found by filename, not recorded. Append to the file where it is and do not move it: a filename match is evidence, not proof it is this change's doc. |
| `absent` | Nothing recorded and no file matched. | Tell the user: "No design doc found for <feature-name>; no Divergences report." Then continue shipping. |
| `ambiguous` | Several candidates; they followed the first line, one per line. | Show them and ask the user which file is the design doc. Do not choose one yourself by date or by any other rule. If the user names a file, generate the report from it and begin the section with a line saying the user chose it. If there is no answer, say no Divergences report was written and continue shipping. |
| `stale` | A path was recorded and its file was already gone when Step 3 looked. | Show the recorded path and ask the user which file is the design doc. If the user names a file, generate the report from it and begin the section with a line saying the user chose it. If there is no answer, say no Divergences report was written and continue shipping. |
| exit 3, no output line | Could not check: a state file exists and is not readable as one JSON object of the expected shape, or `jq` is missing. | Say "could not check for a design doc; no Divergences report". This is not the same as `absent`. Then continue shipping. |

## When the doc resolves but is thin

- No **Acceptance Scenarios** section: say "design doc has no acceptance scenarios; divergences compared on capabilities and scope only", and compare on those.
- Neither section: say so and write no report. An empty Divergences section reads as "nothing diverged".

## Why this is a script and not a remembered path

The path used to come only from a state write the model was asked to perform during DESIGN. That request was a per-prompt hint, since removed; when it was shown, 5 of 188 sessions performed the write. This skill therefore looks for the doc itself.
