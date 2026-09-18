#!/bin/bash
# pilot-capture.sh — deterministic light+dark screenshots of a local HTML file.
#
# Instrument-side only. This is deliberately NOT added to the subject repo: the
# pilot's argument is that the screen needs no frontend toolchain, and standing
# one up in the subject to take its picture would undercut that.
#
# Frozen: viewport 1440x900, deviceScaleFactor 1, animations/transitions/caret
# disabled, both colour schemes via prefers-color-scheme emulation. Playwright
# is pinned to an exact version (never left to float) since an unpinned tool
# is itself a nondeterminism source in a harness whose job is determinism.
set -u
_die() { printf 'pilot-capture: %s\n' "$*" >&2; exit 1; }
[ $# -eq 2 ] || _die "usage: pilot-capture.sh <input.html> <out-dir>"
_IN="$1"; _OUT="$2"
[ -r "${_IN}" ] || _die "unreadable input: ${_IN}"
command -v npx  >/dev/null 2>&1 || _die "npx unavailable"
command -v node >/dev/null 2>&1 || _die "node unavailable"
mkdir -p "${_OUT}" || _die "cannot create ${_OUT}"

_PW_VERSION="1.47.0"
_ABS="$(cd "$(dirname "${_IN}")" && pwd)/$(basename "${_IN}")"

# --- Resolve the 'playwright' package by absolute path, not by bare specifier. ---
# npx's ephemeral install (via `npx --package playwright@X node script.js`) does
# NOT put the package on Node's module resolution path for either CJS `require`
# or ESM `import` (measured: npx only prepends its cache's node_modules/.bin to
# PATH — it does not set NODE_PATH, and NODE_PATH is ignored by ESM regardless).
# A script relying on `require('playwright')`/`import ... from 'playwright'`
# under that invocation fails outright. Fetching the package once via `npx` and
# then requiring it from Node directly, by its resolved absolute path, sidesteps
# both problems and needs no npx wrapper for the actual capture run.
#
# Resolve from disk first — a repeated capture (the common case: Task 9 calls
# this twice more per artifact) must not pay an `npx` resolution on every call.
# `npx` runs only the first time, to populate the cache. Multiple npx-cached
# package hashes can coexist (different versions resolved at different times),
# so match on the pinned version's own package.json rather than taking the
# first "node_modules/playwright" directory `find` happens to list.
_NPM_CACHE="$(npm config get cache 2>/dev/null)"
[ -n "${_NPM_CACHE}" ] || _die "cannot resolve npm cache dir"

_find_pinned_pw_dir() {
    find "${_NPM_CACHE}/_npx" -maxdepth 4 -type d -path '*/node_modules/playwright' 2>/dev/null | \
    while IFS= read -r _cand; do
        if [ -f "${_cand}/package.json" ] && grep -q "\"version\": \"${_PW_VERSION}\"" "${_cand}/package.json" 2>/dev/null; then
            printf '%s\n' "${_cand}"
            break
        fi
    done
}

_PW_DIR="$(_find_pinned_pw_dir)"
if [ -z "${_PW_DIR}" ]; then
    npx --yes "playwright@${_PW_VERSION}" --version >/dev/null 2>&1
    _PW_DIR="$(_find_pinned_pw_dir)"
fi
[ -n "${_PW_DIR}" ] && [ -d "${_PW_DIR}" ] || _die "playwright@${_PW_VERSION} not found in npx cache after fetch"

_CHROME_BIN="$(node -e "
  const { chromium } = require(process.argv[1]);
  process.stdout.write(chromium.executablePath());
" "${_PW_DIR}" 2>/dev/null)"
[ -n "${_CHROME_BIN}" ] || _die "could not resolve chromium executable path"

# Playwright's own marker of a complete install (see registry/oopDownloadBrowserMain.js's
# browserDirectoryToMarkerFilePath). Checking only the executable bit is not enough: a
# killed-mid-extraction attempt can leave a partial binary that is still `-x`.
#
# The browser directory itself is always named "chromium-<revision>", but the
# path FROM there to the executable is platform-specific (mac: 5 components
# via chrome-mac/Chromium.app/Contents/MacOS/Chromium; linux: 2 components via
# chrome-linux/chrome — confirmed against playwright-core's own registry
# source). A hardcoded dirname walk depth is therefore correct on exactly one
# platform and silently wrong on the others (on Linux it overshoots well past
# the real browser directory and checks for a marker Playwright never writes
# there, so the install would always look unfinished). Search upward for the
# "chromium-*" directory name instead, which both platforms in fact share.
_BROWSER_DIR="$(dirname "${_CHROME_BIN}")"
_DEPTH=0
while [ "${_DEPTH}" -lt 10 ]; do
    case "$(basename "${_BROWSER_DIR}")" in
        chromium-*) break ;;
    esac
    _PARENT="$(dirname "${_BROWSER_DIR}")"
    [ "${_PARENT}" = "${_BROWSER_DIR}" ] && break
    _BROWSER_DIR="${_PARENT}"
    _DEPTH=$(( _DEPTH + 1 ))
done
case "$(basename "${_BROWSER_DIR}")" in
    chromium-*) ;;
    *) _die "could not locate a chromium-* browser directory above ${_CHROME_BIN}" ;;
esac
_INSTALL_MARKER="${_BROWSER_DIR}/INSTALLATION_COMPLETE"

_chromium_ready() { [ -f "${_INSTALL_MARKER}" ] && [ -x "${_CHROME_BIN}" ]; }

if ! _chromium_ready; then
    printf 'pilot-capture: chromium not installed, installing (may take a while)...\n' >&2
    ( npx --yes "playwright@${_PW_VERSION}" install chromium >/dev/null 2>&1 ) < /dev/null &
    _INSTALL_PID=$!
    # 60s is generous: measured download of the pinned Chromium build completes
    # in ~16s in this environment. A stalled extraction never makes further
    # progress no matter how long we wait (measured to 300s+), so a short,
    # bounded wait before self-healing costs far less than a long one for the
    # same outcome.
    _WAITED=0
    while ! _chromium_ready && [ "${_WAITED}" -lt 60 ]; do
        sleep 3
        _WAITED=$(( _WAITED + 3 ))
    done

    if ! _chromium_ready; then
        # Self-heal a reproducible stall: the download completes but Playwright's
        # bundled pure-JS zip extractor (extract-zip/yauzl) never finishes writing
        # the browser out — observed consistently in this environment (writes stop
        # partway through the main executable and the process never progresses
        # again). The download itself is reliable; only extraction stalls. macOS's
        # native `ditto` extracts the same zip correctly in well under a second, so
        # recover by finishing the extraction ourselves from the already-downloaded
        # archive instead of leaving the caller hung.
        #
        # Kill only OUR OWN install's process tree — this machine's execution
        # model is explicitly concurrent sessions, and a machine-wide `pkill -f`
        # on the installer's script name would kill another session's install
        # too (this is not hypothetical: two installs raced over the same
        # ms-playwright lock earlier in this work). Walk descendants of the
        # subshell we spawned, rather than pattern-matching every process on
        # the box.
        _kill_descendants() {
            local _p="$1"
            local _c
            for _c in $(pgrep -P "${_p}" 2>/dev/null); do
                _kill_descendants "${_c}"
            done
            kill "${_p}" 2>/dev/null
        }
        _kill_descendants "${_INSTALL_PID}"

        _RECOVERED=1
        if [ "$(uname)" = "Darwin" ] && command -v ditto >/dev/null 2>&1; then
            _ZIP="$(ls -t "${TMPDIR:-/tmp}"/playwright-download-chromium-*.zip 2>/dev/null | head -1)"
            if [ -n "${_ZIP}" ] && [ -s "${_ZIP}" ]; then
                # Require the download to be stable (not still growing) before trusting it.
                _SZ1=$(wc -c < "${_ZIP}" 2>/dev/null)
                sleep 1
                _SZ2=$(wc -c < "${_ZIP}" 2>/dev/null)
                if [ -n "${_SZ1}" ] && [ "${_SZ1}" = "${_SZ2}" ]; then
                    mkdir -p "${_BROWSER_DIR}"
                    if ditto -x -k "${_ZIP}" "${_BROWSER_DIR}" 2>/dev/null; then
                        chmod +x "${_CHROME_BIN}" 2>/dev/null
                        : > "${_INSTALL_MARKER}"
                        # A killed install never removes its own coordination lock;
                        # clear it so a later, ordinary install doesn't see it as
                        # stale-but-active and wait on a process that no longer exists.
                        rm -rf "$(dirname "${_BROWSER_DIR}")/__dirlock" 2>/dev/null
                        _chromium_ready && _RECOVERED=0
                    fi
                fi
            fi
        fi
        [ "${_RECOVERED}" -eq 0 ] || _die "chromium install stalled and automatic recovery was not possible on this platform"
    fi
fi
_chromium_ready || _die "chromium executable missing after install"

cat > "${_OUT}/.capture.cjs" <<'JS'
const { chromium } = require(process.argv[2]);
const url = process.argv[3];
const outDir = process.argv[4];
(async () => {
  const browser = await chromium.launch();
  for (const scheme of ['light', 'dark']) {
    const ctx = await browser.newContext({
      viewport: { width: 1440, height: 900 },
      deviceScaleFactor: 1,
      colorScheme: scheme,
      reducedMotion: 'reduce',
    });
    const page = await ctx.newPage();
    await page.goto(url, { waitUntil: 'load' });
    await page.addStyleTag({ content: '*,*::before,*::after{animation:none!important;transition:none!important;caret-color:transparent!important}' });
    await page.screenshot({ path: `${outDir}/${scheme}.png`, fullPage: true, animations: 'disabled' });
    await ctx.close();
  }
  await browser.close();
})().catch(e => { console.error(e); process.exit(1); });
JS

node "${_OUT}/.capture.cjs" "${_PW_DIR}" "file://${_ABS}" "${_OUT}" \
    || _die "capture failed"

rm -f "${_OUT}/.capture.cjs"
printf 'captured light.png and dark.png in %s\n' "${_OUT}"
