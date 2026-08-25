# Design: Eval-report intake repair

## Architecture

One jq program in `json_eval_reports()` decides what becomes evidence:

```
gh issue list --search '"Behavioral eval regression" in:title'
        |
        v  raw  (phrase-CONTAINS match, not prefix)
   filter: norm_login == "github-actions"
       AND .author.is_bot == true
       AND titled_ok                       -> eval_reports[]
        |
        v  diagnostics (stderr only; stdout stays parseable JSON)
   n_titled > 0 && n_kept == 0  -> WARNING: author allowlist rejected all
   n_titled == 0 && n_raw > 0   -> NOTE: no title matched the prefix
```

`norm_login` strips a leading `app/` and a trailing `[bot]`, then compares to
one name. `titled_ok` is `(.title | type) == "string" and (.title | startswith($pfx))`
and is used **identically** in the filter and in the denominator, so the count
measures exactly what the filter's title clause would accept.

## Decisions & Trade-offs

**Normalise, don't enumerate literals.** Pinning one literal is what created
this defect, and the accompanying comment defended the wrong one for the
skill's whole life. Matching a normalised form tolerates the three spellings gh
has used without enumerating them at the call site.

**`is_bot == true`, not `!= false`.** `!= false` admits an *absent* field. This
entire issue was gh changing the shape of `.author`, so the clause must require
the field rather than tolerate its disappearance. Failing closed costs a loud
warning; failing open costs an attacker-authored body reaching the model as
trusted evidence. Rejected: relying on the login alone, since bare
`github-actions` is registerable-shaped in a way `app/…` and `…[bot]` are not.

**Type-safe title, and exclusion rather than abort.** jq short-circuits, so an
unguarded `startswith` is only safe for elements the login *rejects* — on an
allowlisted bot's issue, exactly the drift case this code defends, a non-string
title killed the entire bundle. A title that is not a string is simply not a
correctly-titled eval report, so the element is excluded. One malformed issue
must not take down a mining run.

**Two advisories, not one, and not zero.** The first cut of the warning
attributed every empty intake to the author allowlist, including cases the
title check rejected — a message committing to a cause it had not established,
prescribing the wrong remedy. Narrowing its trigger fixed the misattribution
but deleted detection for the title-drift case. Both causes are real and have
different remedies, so both are announced, separately worded. Rejected:
warning whenever `n_kept < n_titled`, which fires forever in any repo where a
human once filed a prefix-titled issue.

**No "cannot count" arm.** An earlier revision guarded against an uncomputable
denominator. With a type-safe title test the count cannot fail on any input
where the filter succeeded, and if the filter failed the run already exited 5.
A guard for an unreachable state is prose no test can kill — the same failure
mode this change exists to correct — so it was removed rather than kept as a
belt.

**Advisory, not fatal.** The script's fail-loud posture covers *inability to
check* (`gh` non-zero, unparseable JSON). An intake that evaluated the boundary
and rejected everything is a legitimate steady state — a repo may have only
human-authored issues under that title prefix. Making it fatal would hard-stop
every mine there, and the pressure would then be to relax the allowlist to get
the tool working: a fatal error here converts a diagnostic into pressure on the
trust boundary.

## Dependencies

None added. `gh` and `jq` were already required; the fail-loud paths on their
failure are unchanged.

## Implementation Notes

Four review rounds, seven defects, and **every round found a real defect in the
preceding round's fix**. The full suite was green at each of those points, as
was a mutation matrix at three of them. Recorded because the pattern is the
main engineering lesson of this change, not an anecdote:

1. r1 → the advisory named the wrong remedy; `is_bot` was fail-open; the
   title clause had zero coverage; a stale test still passed with the original
   defect reinstated by mutation.
2. r2 → the fix for the wrong-remedy advisory re-opened this issue's own class
   through the code written to detect it (a null title silenced a genuine
   author drift), and the README fix introduced a fresh overclaim.
3. r3 → two r2 assertions were vacuous: one matched both the fixed and the
   fallback path, the other tested an unreachable branch. Caught only by
   mutation testing.
4. r4 → r3 hardened the diagnostic count and left the load-bearing filter
   unguarded, with a comment asserting a short-circuit protection that does not
   hold when the login matches.

Two artifacts encoded confidently-wrong claims and had to be corrected more
than once: a code comment defending the wrong literal, and the fixture README's
coverage table. Both were written while fixing a previous wrong claim.
