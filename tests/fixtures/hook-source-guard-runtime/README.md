# hook-source-guard-runtime fixtures (issue #192)

Each `fault-*.sh` is ONE failure shape that a sourced lib can exhibit *while it
is being sourced*, injected verbatim into a copy of a real `hooks/lib/*.sh`.

They exist as committed files, one shape per file, because the defect they pin
is invisible to every other gate in the repo: `bash -n` sees a parse-clean
file, the #137 status lint sees a correctly-guarded `. lib && flag || true`
call site, and the session-start canary only source-probes the five
`_GATE_ENFORCE_LIBS` — none of them execute the guard.

`control-return-1.sh` is NOT a #192 shape: `return 1` aborts the source and is
already handled by #137's guarded-source form. It is kept as the red control
that proves the harness can tell the two classes apart.

Injection point matters and both are exercised by the test:

  early — inserted after the shebang, i.e. BEFORE the lib defines anything.
          Post-fix the source must still run to completion, so every function
          is defined anyway and the gate decision is unchanged.
  late  — appended, i.e. after every definition. Pre-fix this still killed the
          hook, which is the cleanest proof that the failure is the ERR trap
          and not a missing function.
