# verdict-dirty-tree fixtures (#274) — NEVER DELETE

Three verdict records, each a clean PASS covering `@SHA@`, differing only in the
measurement-context fields. `@SHA@` is substituted with the fixture repo's HEAD
at run time by `tests/test-verdict-dirty-tree.sh`.

| file | `worktree_dirty` | `dirty_paths` | what it pins |
|---|---|---|---|
| `clean-tree.json` | `false` | `[]` | the CONTROL: no advisory may be added |
| `dirty-with-paths.json` | `true` | 2 paths | the advisory names the paths |
| `dirty-legacy-no-paths.json` | `true` | absent | a pre-#274 record: dirty, but cannot say where |
| `dirty-truncated.json` | `true` | 20 stored, count 37 | the remainder is counted against the TRUE total, and the cap is a fact about the RECORD |

The third is the one that is easy to get wrong. "Dirty and we do not know which
paths" and "dirty in these two files" are different states, and collapsing them
either fabricates a path list or drops the warning entirely. Records written
before #274 carry no `dirty_paths` key at all, and they will keep arriving from
any older plugin in the versioned cache.

The fourth exists because the first cut of `verdict_dirty_note` mixed two
populations: `+k more` counted the STORED list while `(list truncated)` counted
the recorded cap, so 20 stored of 37 dirty paths read `37 path(s): a…e, +15
more (list truncated)` — and neither number was the 32 a reader wants. With 2
paths and a count of 2, `dirty-with-paths.json` can never show that.
