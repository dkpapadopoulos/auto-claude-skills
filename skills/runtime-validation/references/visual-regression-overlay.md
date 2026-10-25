# runtime-validation — visual-regression overlay script

Read at SKILL.md Step 3 before running the visual-regression overlay (Playwright is available). The overlay's rules (report-only, never hard-blocks, first run seeds a baseline) stay in SKILL.md. Moved verbatim from SKILL.md.

```bash
# Baselines: tests/artifacts/validation/visual-baselines/  (gitignored, persists across runs)
# Actuals + diffs: tests/artifacts/validation/visual-runs/
BASELINE_DIR="$(pwd)/tests/artifacts/validation/visual-baselines"
mkdir -p "${BASELINE_DIR}" tests/artifacts/validation/visual-runs

# Route Playwright's snapshots to the PERSISTENT baseline dir (default is a
# <spec>-snapshots/ folder beside the spec — which here is the mktemp dir that
# gets rm -rf'd, so baselines would never survive). snapshotPathTemplate fixes that.
cat > "${VALIDATION_TMPDIR}/pw.config.ts" << EOCFG
import { defineConfig } from '@playwright/test';
export default defineConfig({
  snapshotPathTemplate: '${BASELINE_DIR}/{arg}{ext}',
  outputDir: '$(pwd)/tests/artifacts/validation/visual-runs',
});
EOCFG
cat > "${VALIDATION_TMPDIR}/visual.spec.ts" << 'EOTEST'
import { test, expect } from '@playwright/test';
test('homepage visual', async ({ page }) => {
  await page.goto(process.env.PERF_URL || 'http://localhost:3000/');
  await page.waitForLoadState('networkidle');
  await expect(page).toHaveScreenshot('homepage.png', { maxDiffPixelRatio: 0.02 });
});
EOTEST

# argv array (not a string) so paths with spaces never word-split the invocation.
PW=(npx playwright test --config "${VALIDATION_TMPDIR}/pw.config.ts" "${VALIDATION_TMPDIR}/visual.spec.ts")
# First run: no baseline yet → seed it (BASELINE_MISSING/SEEDED, not pass/fail).
# Later runs: the baseline persists in visual-baselines/ → diff → MATCH or CHANGED.
if [ -z "$(ls -A "${BASELINE_DIR}" 2>/dev/null)" ]; then
  "${PW[@]}" --update-snapshots 2>/dev/null \
    && echo "visual: BASELINE_MISSING/SEEDED (baseline captured under visual-baselines/ — list in Coverage Gaps)"
else
  "${PW[@]}" 2>/dev/null && echo "visual: MATCH" || echo "visual: CHANGED (see diff under visual-runs/)"
fi
```
