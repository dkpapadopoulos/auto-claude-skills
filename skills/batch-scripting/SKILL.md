---
name: batch-scripting
description: Use when transforming, migrating, refactoring, or generating across many files at once — codebase-wide renames, 50+ file migrations, mass test/doc generation, framework upgrades — via claude -p with manifest, dry-run, and log-based retry
---

# Batch Scripting

Structured protocol for bulk file operations using `claude -p`. Teaches a safe, resumable pattern — not a framework.

## When to Use

- Large-scale transforms (migrate 50+ files from one pattern to another)
- Bulk refactoring (rename across codebase, update imports, convert syntax)
- Batch code generation (add tests, docs, or boilerplate to many files)
- Codebase-wide migrations (CommonJS to ESM, API version bumps, framework upgrades)

## Protocol

### Step 1: Enumerate targets (manifest)

Build the full file list FIRST. Show it to the user. Get explicit approval before proceeding.

```bash
# Session-scoped working directory — prevents concurrent session collisions
BATCH_DIR=$(mktemp -d /tmp/agent-batch-XXXXXX)

# Generate manifest — adapt the glob/grep to the specific task
find src -name "*.ts" -not -path "*/node_modules/*" > "$BATCH_DIR/manifest.txt"
echo "Found $(wc -l < "$BATCH_DIR/manifest.txt") files. Review the list:"
cat "$BATCH_DIR/manifest.txt"
```

Never skip manifest review. The user must see and approve the file list.

### Step 2: Dry run (2-3 files)

Process 2-3 representative files first. Show full diffs. Get user approval before the full run.

```bash
# Pick representative files (first, middle, last)
head -1 "$BATCH_DIR/manifest.txt" | xargs -I{} claude -p "Transform {} as follows: [PROMPT]. Output ONLY the transformed file content." > "$BATCH_DIR/dry-run-output.txt"
diff /path/to/original "$BATCH_DIR/dry-run-output.txt"
```

If the dry run does not look right, adjust the prompt and re-run. Do NOT proceed to the full batch with a bad prompt.

### Step 3: Execute with logging

Loop over the manifest. Log pass/fail per file. Use atomic writes (write to .tmp, then move).

```bash
while IFS= read -r file; do
  if claude -p "Transform $file as follows: [PROMPT]. Output ONLY the file content." > "${file}.tmp" 2>/dev/null; then
    mv "${file}.tmp" "$file"
    echo "OK: $file" >> "$BATCH_DIR/results.log"
  else
    rm -f "${file}.tmp"
    echo "FAIL: $file" >> "$BATCH_DIR/results.log"
  fi
done < "$BATCH_DIR/manifest.txt"
```

### Step 4: Handle failures (log-based retry)

After the batch, check the log. Re-run only the failures.

```bash
# Check results
echo "Results:"
grep -c "^OK:" "$BATCH_DIR/results.log"
grep -c "^FAIL:" "$BATCH_DIR/results.log"

# Retry failures
grep "^FAIL:" "$BATCH_DIR/results.log" | cut -d' ' -f2 > "$BATCH_DIR/retry.txt"
# Re-run step 3 with $BATCH_DIR/retry.txt as input
```

### Step 5: Verify

After the full batch completes, run the project's test suite and linter. Review the full git diff.

```bash
# Run tests
[project test command]

# Review scope of changes
git diff --stat
git diff  # full diff for review

# Clean up session directory
rm -rf "$BATCH_DIR"
```

### Step 6: Checkpoint for large batches

For 100+ files, process in chunks of 20. Pause between chunks for user confirmation.

```bash
split -l 20 "$BATCH_DIR/manifest.txt" "$BATCH_DIR/chunk-"
for chunk in "$BATCH_DIR/chunk-"*; do
  echo "Processing chunk: $chunk ($(wc -l < "$chunk") files)"
  # Run step 3 loop on this chunk
  echo "Chunk complete. Continue? [y/n]"
done
```

## Anti-patterns

- **No JSON state files** — a text log is sufficient. `grep FAIL` is your resume mechanism.
- **No rate-limit backoff logic** — `claude -p` handles its own rate limiting. If you hit limits, reduce chunk size or wait.
- **No rollback infrastructure** — git IS your rollback. Run the batch on a branch, review, revert if bad.
- **No progress bars** — `wc -l "$BATCH_DIR/results.log"` tells you where you are.
- **Never write in-place without .tmp** — always write to a temp file, verify, then move.

## Integration

- Pairs with `verification-before-completion` after batch completes
- Use a git branch for rollback, not custom undo logic
- For interactive (non-headless) batch work, consider `dispatching-parallel-agents` instead
