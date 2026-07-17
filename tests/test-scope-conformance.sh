#!/bin/bash
# test-scope-conformance.sh — scripts/scope-conformance.sh verdict tests.
# Self-contained: builds throwaway git repos; no test-helpers dependency.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUT="${SCRIPT_DIR}/../scripts/scope-conformance.sh"
PASS=0; FAIL=0

assert_exit() { # desc expected actual
    if [ "$2" -eq "$3" ]; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL: $1 (expected exit $2, got $3)"; fi
}
assert_contains() { # desc needle haystack-file
    if grep -F -q "$2" "$3"; then PASS=$((PASS + 1)); else
        FAIL=$((FAIL + 1)); echo "FAIL: $1 (missing: $2)"; fi
}

make_repo() { # $1 = dir; exits the suite on setup failure (a silent cd back
              # into the previous temp repo would corrupt every later case)
    mkdir -p "$1" && cd "$1" || { echo "FATAL: repo setup failed for $1"; exit 1; }
    git init -q -b main . 2>/dev/null || { git init -q .; git checkout -q -b main; }
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
    mkdir -p scripts hooks tests
    echo base > scripts/foo.sh
    echo base > hooks/bar.sh
    git add . && git -c user.email=t@t -c user.name=t commit -q -m files
    git checkout -q -b feature
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/scopeconf.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out.txt"

# --- Case 1: clean — only declared file changed -----------------------------
make_repo "$TMP/clean"
cat > plan.md <<'EOF'
### Task 1: thing
**Files:**
- Modify: `scripts/foo.sh`
EOF
echo changed > scripts/foo.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "clean branch exits 0" 0 "$rc"
assert_contains "clean verdict printed" "scope-conformance: clean" "$OUT"

# --- Case 2: violation — undeclared file changed ----------------------------
make_repo "$TMP/viol"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
EOF
echo changed > scripts/foo.sh
echo rogue > hooks/bar.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "out-of-scope edit exits 1" 1 "$rc"
assert_contains "violation lists file" "hooks/bar.sh" "$OUT"

# --- Case 3: violation — out-of-scope DELETE (the recorded incident) --------
make_repo "$TMP/del"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
EOF
rm hooks/bar.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "out-of-scope delete exits 1" 1 "$rc"
assert_contains "delete listed" "hooks/bar.sh" "$OUT"

# --- Case 4: unverified — no plan file --------------------------------------
make_repo "$TMP/noplan"
bash "$SUT" missing-plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "missing plan exits 2" 2 "$rc"
assert_contains "unverified verdict" "unverified" "$OUT"

# --- Case 5: unverified — plan with no Files entries ------------------------
make_repo "$TMP/emptyplan"
echo "# just prose" > plan.md
echo changed > scripts/foo.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "entry-less plan exits 2" 2 "$rc"

# --- Case 6: line-range suffix stripped -------------------------------------
make_repo "$TMP/range"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh:3-9`
EOF
echo changed > scripts/foo.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "range-suffixed entry matches" 0 "$rc"

# --- Case 7: Allow glob covers untracked file -------------------------------
make_repo "$TMP/allow"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
- Allow: `tests/*`
EOF
echo changed > scripts/foo.sh
echo new > tests/test-new.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "Allow glob covers untracked" 0 "$rc"

# --- Case 8: meta allowlist (CHANGELOG.md) always covered -------------------
make_repo "$TMP/meta"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
EOF
echo changed > scripts/foo.sh
echo entry > CHANGELOG.md
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "CHANGELOG.md exempt via meta allowlist" 0 "$rc"

# --- Case 9: diverged mainline + EXPLICIT base — no false violation ---------
make_repo "$TMP/diverge"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
EOF
echo changed > scripts/foo.sh
git add . && git -c user.email=t@t -c user.name=t commit -q -m feat
git checkout -q main
echo mainline > main-only.txt
git add . && git -c user.email=t@t -c user.name=t commit -q -m mainchurn
git checkout -q feature
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "explicit base on diverged main exits 0 (merge-base normalized)" 0 "$rc"

# --- Case 10: automatic base resolution (no base arg) -----------------------
make_repo "$TMP/autobase"
cat > plan.md <<'EOF'
**Files:**
- Modify: `scripts/foo.sh`
EOF
echo changed > scripts/foo.sh
bash "$SUT" plan.md > "$OUT" 2>&1; rc=$?
assert_exit "auto-resolved base (local main) exits 0" 0 "$rc"

# --- Case 11: trailing-slash directory entry covers contained files ---------
make_repo "$TMP/direntry"
cat > plan.md <<'EOF'
**Files:**
- Create: `newdir/`
EOF
mkdir -p newdir
echo impl > newdir/impl.sh
bash "$SUT" plan.md main > "$OUT" 2>&1; rc=$?
assert_exit "dir/ entry covers contained file" 0 "$rc"

echo "test-scope-conformance: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ]
