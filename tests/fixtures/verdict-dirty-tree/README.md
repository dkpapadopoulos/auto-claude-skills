# verdict-dirty-tree fixtures (#274) — NEVER DELETE

Three verdict records, each a clean PASS covering `@SHA@`, differing only in the
measurement-context fields. `@SHA@` is substituted with the fixture repo's HEAD
at run time by `tests/test-verdict-dirty-tree.sh`.

| file | `worktree_dirty` | `dirty_paths` | what it pins |
|---|---|---|---|
| `clean-tree.json` | `false` | `[]` | the CONTROL: no advisory may be added |
| `dirty-with-paths.json` | `true` | 2 paths | the advisory names the paths |
| `dirty-legacy-no-paths.json` | `true` | absent | a pre-#274 record: dirty, but cannot say where |

The third is the one that is easy to get wrong. "Dirty and we do not know which
paths" and "dirty in these two files" are different states, and collapsing them
either fabricates a path list or drops the warning entirely. Records written
before #274 carry no `dirty_paths` key at all, and they will keep arriving from
any older plugin in the versioned cache.
