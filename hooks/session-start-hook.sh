#!/bin/bash
# --- Session Start Hook: Skill Registry Builder -------------------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Runs at SessionStart. Scans plugin cache and user skills, merges
# with default triggers, applies user config overrides, and caches
# the result as ~/.claude/.skill-registry-cache.json.
#
# Output format:
#   {"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"..."}}
#
# Bash 3.2 compatible (macOS default). No associative arrays.
# -----------------------------------------------------------------
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# -----------------------------------------------------------------
# Step 1: Run fix-plugin-manifests.sh (backwards compat)
# -----------------------------------------------------------------
FIX_SCRIPT="${PLUGIN_ROOT}/hooks/fix-plugin-manifests.sh"
if [ -f "${FIX_SCRIPT}" ]; then
    bash "${FIX_SCRIPT}" 2>/dev/null || true
fi

# -----------------------------------------------------------------
# Step 1b: Ensure cozempic is available (context protection)
# -----------------------------------------------------------------
if ! command -v cozempic >/dev/null 2>&1; then
    # Check common install locations before warning
    for _p in "$HOME/.local/bin" "$HOME/Library/Python"/*/bin; do
        [ -x "$_p/cozempic" ] && export PATH="$_p:$PATH" && break
    done
fi
if command -v cozempic >/dev/null 2>&1; then
    cozempic init >/dev/null 2>&1 || true
else
    printf '[session-start] cozempic not found. Install with: pip install cozempic\n' >&2
fi

# -----------------------------------------------------------------
# Step 1c: Reset depth counter for new session
# -----------------------------------------------------------------
# Token strategy: prefer Claude Code's session_id from hook stdin (stable across
# every SessionStart fire within the same conversation — IDE reloads, panel
# restarts, etc.) so composition-state files keyed off the token survive
# session-start re-fires. Without this, every SessionStart rotated the token
# and orphaned in-flight composition state, blowing up the openspec-guard push
# gate's REVIEW/VERIFY/SHIP checks (see #14, #15).
#
# Falls back to <epoch>-<pid>-<rand> when stdin is unavailable, contains no
# session_id, or jq is missing — preserving the original collision-defense
# guarantees for environments that don't deliver session_id.
_HOOK_STDIN=""
if [ ! -t 0 ]; then
    _HOOK_STDIN="$(cat 2>/dev/null)" || _HOOK_STDIN=""
fi
_HOOK_SESSION_ID=""
if [ -n "${_HOOK_STDIN}" ] && command -v jq >/dev/null 2>&1; then
    _HOOK_SESSION_ID="$(printf '%s' "${_HOOK_STDIN}" | jq -r '.session_id // empty' 2>/dev/null)" || _HOOK_SESSION_ID=""
fi
if [ -n "${_HOOK_SESSION_ID}" ]; then
    _SESSION_TOKEN="session-${_HOOK_SESSION_ID}"
else
    # Fallback for environments without session_id. Format: <epoch>-<pid>-<rand>.
    # The random suffix defends against collisions when two sessions start in the
    # same second with a reused PID (shell respawn, rapid subshell invocation).
    _SESSION_TOKEN="$(date +%s)-$$-${RANDOM}${RANDOM}"
fi
printf '%s' "$_SESSION_TOKEN" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || true
# Read previous session's zero-match stats before cleanup
_PREV_ZM=0
_PREV_TOTAL=0
[[ -f "${HOME}/.claude/.skill-zero-match-count" ]] && _PREV_ZM="$(cat "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null)"
[[ "$_PREV_ZM" =~ ^[0-9]+$ ]] || _PREV_ZM=0
# Sum all prompt counters from previous session
for _pcf in "${HOME}/.claude/.skill-prompt-count-"*; do
    [[ -f "$_pcf" ]] || continue
    _pc="$(cat "$_pcf" 2>/dev/null)"
    [[ "$_pc" =~ ^[0-9]+$ ]] && _PREV_TOTAL=$((_PREV_TOTAL + _pc))
done
rm -f "${HOME}/.claude/.skill-zero-match-count" 2>/dev/null || true
rm -f "${HOME}/.claude/.skill-prompt-count-"* 2>/dev/null || true
printf '0' > "${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN}" 2>/dev/null || true

# -----------------------------------------------------------------
# Step 2: Check jq availability
# -----------------------------------------------------------------
CACHE_FILE="${HOME}/.claude/.skill-registry-cache.json"
mkdir -p "$(dirname "${CACHE_FILE}")"

if ! command -v jq >/dev/null 2>&1; then
    printf '[session-start] jq not found. Install with: brew install jq (macOS) or apt install jq (Linux)\n' >&2
fi

if ! command -v jq >/dev/null 2>&1; then
    FALLBACK="${PLUGIN_ROOT}/config/fallback-registry.json"
    if [ -f "${FALLBACK}" ]; then
        cp "${FALLBACK}" "${CACHE_FILE}"
    else
        printf '{"version":"4.0.0-fallback","warnings":["jq not available, no fallback found"],"skills":[]}\n' > "${CACHE_FILE}"
    fi
    # NOTE: jq unavailable on this path; MSG must remain a simple ASCII string (no quotes or backslashes)
    MSG="SessionStart: jq not found -- skill routing disabled. Install jq: brew install jq (macOS) or apt install jq (Linux)"
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "${MSG}"
    exit 0
fi

# -----------------------------------------------------------------
# Path constants
# -----------------------------------------------------------------
DEFAULT_TRIGGERS="${PLUGIN_ROOT}/config/default-triggers.json"
USER_SKILLS_DIR="${HOME}/.claude/skills"
USER_CONFIG="${HOME}/.claude/skill-config.json"

# Read default triggers once into memory (avoid repeated file I/O)
DEFAULT_JSON=""
if [ -f "${DEFAULT_TRIGGERS}" ]; then
    DEFAULT_JSON="$(cat "${DEFAULT_TRIGGERS}")"
fi
# Pristine snapshot — DEFAULT_JSON may be mutated by preset activation (Step 6c).
# The fallback writer must use this untouched copy to stay machine-agnostic.
DEFAULT_JSON_PRISTINE="${DEFAULT_JSON}"

# -----------------------------------------------------------------
# Frontmatter parser: extract routing metadata from SKILL.md files
# -----------------------------------------------------------------
# Usage: _parse_frontmatter file1 file2 ...
# Output: JSON objects separated by \x1f, one per file
# Each object has optional keys: triggers, role, phase, priority, precedes, requires
# Malformed files produce empty objects.
_parse_frontmatter() {
    [ $# -eq 0 ] && return
    awk '
    BEGIN { first = 1 }
    FNR == 1 {
        if (!first) { emit(); printf "\x1f" }
        first = 0
        in_fm = 0; found_start = 0; done_fm = 0; cur_key = ""; obj = "{"
    }
    /^---[ \t]*$/ {
        if (done_fm) next
        if (!found_start) { found_start = 1; in_fm = 1; next }
        else { in_fm = 0; done_fm = 1; next }
    }
    !in_fm { next }
    /^  - / {
        val = $0; sub(/^  - ["'"'"']?/, "", val); sub(/["'"'"']?[ \t]*$/, "", val)
        if (cur_key != "") {
            if (arr_started) arr = arr ","; else arr_started = 1
            gsub(/\\/, "\\\\", val)
            gsub(/"/, "\\\"", val)
            arr = arr "\"" val "\""
        }
        next
    }
    /^[a-zA-Z_][a-zA-Z0-9_]*:/ {
        if (cur_key != "" && arr_started) {
            if (obj != "{") obj = obj ","
            obj = obj "\"" cur_key "\":[" arr "]"
        }
        cur_key = $0; sub(/:.*/, "", cur_key)
        val = $0; sub(/^[^:]*:[ \t]*/, "", val); sub(/[ \t]*$/, "", val)
        arr = ""; arr_started = 0
        if (val != "" && val !~ /^[ \t]*$/) {
            sub(/^["'"'"']/, "", val); sub(/["'"'"']$/, "", val)
            if (cur_key == "name" || cur_key == "description" || cur_key == "license") {
                cur_key = ""
            } else {
                if (obj != "{") obj = obj ","
                gsub(/\\/, "\\\\", val)
                gsub(/"/, "\\\"", val)
                obj = obj "\"" cur_key "\":\"" val "\""
                cur_key = ""
            }
        } else if (cur_key == "name" || cur_key == "description" || cur_key == "license") {
            cur_key = ""
        }
        next
    }
    function emit() {
        if (cur_key != "" && arr_started) {
            if (obj != "{") obj = obj ","
            obj = obj "\"" cur_key "\":[" arr "]"
        }
        printf "%s", obj "}"
    }
    END { emit() }
    ' "$@"
}

# -----------------------------------------------------------------
# Step 3: Discover all external plugin skills (unified scanner)
# -----------------------------------------------------------------
EXTERNAL_DISCOVERED=""
for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
    [ -d "${_mkt_dir}" ] || continue
    for _plugin_dir in "${_mkt_dir}"*/; do
        [ -d "${_plugin_dir}" ] || continue
        _pname="$(basename "${_plugin_dir}")"
        # Skip self (bundled skills handled separately in Step 4b)
        [ "${_pname}" = "auto-claude-skills" ] && continue

        # Resolve version dir: filter to strict semver, pick latest
        _resolved="${_plugin_dir}"
        _latest_ver="$(ls -1 "${_plugin_dir}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
        if [ -n "${_latest_ver}" ]; then
            _resolved="${_plugin_dir}${_latest_ver}/"
        fi

        # Scan skills
        if [ -d "${_resolved}skills" ]; then
            for _smd in "${_resolved}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _sname="$(basename "$(dirname "${_smd}")")"
                EXTERNAL_DISCOVERED="${EXTERNAL_DISCOVERED}${_sname}|Skill(${_pname}:${_sname})
"
            done
        fi
    done
done

# -----------------------------------------------------------------
# Step 4b: Discover skills bundled with this plugin
# -----------------------------------------------------------------
PLUGIN_SKILLS_DIR="${PLUGIN_ROOT}/skills"
PLUGIN_DISCOVERED=""
if [ -d "${PLUGIN_SKILLS_DIR}" ]; then
    for skill_md in "${PLUGIN_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        PLUGIN_DISCOVERED="${PLUGIN_DISCOVERED}${skill_name}|Skill(auto-claude-skills:${skill_name})
"
    done
fi

# -----------------------------------------------------------------
# Step 5: Discover user-installed skills
# Skip any that share a name with plugin-bundled skills (avoid dupes)
# -----------------------------------------------------------------
USER_DISCOVERED=""
if [ -d "${USER_SKILLS_DIR}" ]; then
    for skill_md in "${USER_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${skill_md}" ] || continue
        skill_name="$(basename "$(dirname "${skill_md}")")"
        # Skip if already discovered as a plugin-bundled skill
        if printf '%s' "${PLUGIN_DISCOVERED}" | grep -q "^${skill_name}|"; then
            continue
        fi
        USER_DISCOVERED="${USER_DISCOVERED}${skill_name}|Skill(${skill_name})
"
    done
fi

# -----------------------------------------------------------------
# Combine all discovered skills into one list
# -----------------------------------------------------------------
ALL_DISCOVERED="${EXTERNAL_DISCOVERED}${PLUGIN_DISCOVERED}${USER_DISCOVERED}"

# -----------------------------------------------------------------
# Step 5b: Extract frontmatter from all discovered SKILL.md files
# -----------------------------------------------------------------
_FM_FILES=""
_FM_NAMES=""

# Scan all external plugins (same traversal as unified scanner in Step 3)
for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
    [ -d "${_mkt_dir}" ] || continue
    for _plugin_dir in "${_mkt_dir}"*/; do
        [ -d "${_plugin_dir}" ] || continue
        _pname="$(basename "${_plugin_dir}")"
        [ "${_pname}" = "auto-claude-skills" ] && continue
        _resolved="${_plugin_dir}"
        _latest_ver="$(ls -1 "${_plugin_dir}" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)"
        if [ -n "${_latest_ver}" ]; then
            _resolved="${_plugin_dir}${_latest_ver}/"
        fi
        if [ -d "${_resolved}skills" ]; then
            for _smd in "${_resolved}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _FM_FILES="${_FM_FILES} ${_smd}"
                _FM_NAMES="${_FM_NAMES}$(basename "$(dirname "${_smd}")")
"
            done
        fi
    done
done

if [ -d "${PLUGIN_SKILLS_DIR}" ]; then
    for _smd in "${PLUGIN_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${_smd}" ] || continue
        _FM_FILES="${_FM_FILES} ${_smd}"
        _FM_NAMES="${_FM_NAMES}$(basename "$(dirname "${_smd}")")
"
    done
fi

if [ -d "${USER_SKILLS_DIR}" ]; then
    for _smd in "${USER_SKILLS_DIR}"/*/SKILL.md; do
        [ -f "${_smd}" ] || continue
        _FM_FILES="${_FM_FILES} ${_smd}"
        _FM_NAMES="${_FM_NAMES}$(basename "$(dirname "${_smd}")")
"
    done
fi

FRONTMATTER_MAP="{}"
if [ -n "${_FM_FILES}" ]; then
    _fm_raw="$(_parse_frontmatter ${_FM_FILES})"
    if [ -n "${_fm_raw}" ]; then
        FRONTMATTER_MAP="$(printf '%s' "${_FM_NAMES}" | jq -Rn --argjson objs "[$(printf '%s' "${_fm_raw}" | tr $'\x1f' ',')]" '
            [inputs | select(. != "")] as $names |
            [range(0; [$names | length, ($objs | length)] | min) as $i |
                {($names[$i]): $objs[$i]}] | add // {}
        ')" || FRONTMATTER_MAP="{}"
    fi
fi

# -----------------------------------------------------------------
# Step 6: Three-tier merge — frontmatter > default-triggers > generic
# -----------------------------------------------------------------
# Build invoke map from ALL_DISCOVERED as a JSON object {"name":"invoke_path",...}
# Single jq call instead of per-skill lookups
if [ -n "${ALL_DISCOVERED}" ]; then
    INVOKE_MAP="$(printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r _n _p; do
        [ -z "${_n}" ] && continue
        printf '%s\n%s\n' "${_n}" "${_p}"
    done | jq -Rn '[inputs] | [range(0; length; 2) as $i | {(.[($i)]): .[($i)+1]}] | add // {}')"
else
    INVOKE_MAP="{}"
fi

# Three-tier merge: frontmatter overrides > default-triggers > generic defaults
if [ -n "${DEFAULT_JSON}" ]; then
    SKILLS_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq \
        --argjson imap "${INVOKE_MAP}" \
        --argjson fmap "${FRONTMATTER_MAP}" '
        [.skills[] | . as $skill |
            ($fmap[$skill.name] // {}) as $fm |
            (if ($fm.triggers // null) then {triggers: $fm.triggers} else {} end) as $ft |
            (if ($fm.role // null) then {role: $fm.role} else {} end) as $fr |
            (if ($fm.phase // null) then {phase: $fm.phase} else {} end) as $fp |
            (if ($fm.priority // null) then {priority: ($fm.priority | tonumber)} else {} end) as $fpri |
            (if ($fm.precedes // null) then {precedes: $fm.precedes} else {} end) as $fprec |
            (if ($fm.requires // null) then {requires: $fm.requires} else {} end) as $freq |
            . + $ft + $fr + $fp + $fpri + $fprec + $freq + (
                if $imap[$skill.name] then
                    {invoke: $imap[$skill.name], available: true, enabled: true}
                else
                    {available: false, enabled: true} + (if .invoke then {invoke: .invoke} else {} end)
                end
            )
        ]
    ')"
else
    SKILLS_JSON="[]"
fi

# Extract default skill + plugin names once for custom-skill detection
# Exclude both: skills already in defaults AND names matching plugins (tracked separately)
DEFAULT_NAMES=""
if [ -n "${DEFAULT_JSON}" ]; then
    DEFAULT_NAMES="$(printf '%s' "${DEFAULT_JSON}" | jq -r '(.skills[].name), (.plugins[].name)')"
fi

# Collect custom skills (discovered but not in defaults) and batch-append
# Build newline-delimited name|path pairs, then create all custom entries in one jq call
printf '%s' "${ALL_DISCOVERED}" | while IFS='|' read -r sname spath; do
    [ -z "${sname}" ] && continue
    _found=0
    while IFS= read -r _dn; do
        [ -z "${_dn}" ] && continue
        if [ "${_dn}" = "${sname}" ]; then
            _found=1
            break
        fi
    done <<DNAMES
${DEFAULT_NAMES}
DNAMES
    if [ "${_found}" -eq 0 ]; then
        printf '%s\n%s\n' "${sname}" "${spath}"
    fi
done > "${CACHE_FILE}.customs.$$" 2>/dev/null || true

if [ -f "${CACHE_FILE}.customs.$$" ] && [ -s "${CACHE_FILE}.customs.$$" ]; then
    CUSTOMS_JSON="$(jq -Rn --argjson fmap "${FRONTMATTER_MAP}" '[inputs] | [range(0; length; 2) as $i |
        (.[($i)]) as $name |
        ($fmap[$name] // {}) as $fm |
        {
            name: $name,
            role: ($fm.role // "domain"),
            triggers: ($fm.triggers // []),
            trigger_mode: "regex",
            priority: (($fm.priority // "200") | tonumber),
            phase: ($fm.phase // ""),
            precedes: ($fm.precedes // []),
            requires: ($fm.requires // []),
            description: "Discovered skill",
            invoke: .[($i)+1],
            available: true,
            enabled: true
        }]' < "${CACHE_FILE}.customs.$$")"
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson c "${CUSTOMS_JSON}" '. + $c')"
fi
rm -f "${CACHE_FILE}.customs.$$"

# -----------------------------------------------------------------
# Step 7: Apply user config overrides (single jq call)
# -----------------------------------------------------------------
WARNINGS="[]"

# Step 6b: Resolve preset (if configured in skill-config.json)
_preset_name=""
if [ -f "${USER_CONFIG}" ]; then
  _preset_name="$(jq -r '.preset // ""' "${USER_CONFIG}" 2>/dev/null)"
fi
if [ -n "$_preset_name" ] && [ "$_preset_name" != "null" ]; then
  _preset_file="${PLUGIN_ROOT}/config/presets/${_preset_name}.json"
  if [ -f "$_preset_file" ]; then
    _default_enabled="$(jq -r '.default_enabled // true' "$_preset_file")"
    _preset_overrides="$(jq -c '.overrides // {}' "$_preset_file")"
    if [ "$_default_enabled" = "false" ]; then
      # Disable all skills not in the preset's override list
      SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson po "$_preset_overrides" '
        [.[] |
          if ($po[.name] != null) then
            .enabled = ($po[.name].enabled // true)
          else
            .enabled = false
          end
        ]
      ')"
    fi
    # Apply any explicit overrides from preset
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson po "$_preset_overrides" '
      [.[] |
        if ($po[.name] != null) then
          . + ($po[.name] | del(.enabled)) + { enabled: ($po[.name].enabled // .enabled) }
        else .
        end
      ]
    ')"
    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg m "Preset active: ${_preset_name} (${_preset_file})" '. + [$m]')"
  else
    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg m "Preset '${_preset_name}' not found at ${_preset_file}" '. + [$m]')"
  fi
fi

# Step 6c: Apply openspec_first mode if preset enables it
# Rewrites DESIGN and PLAN phase composition hints to point at
# openspec/changes/ instead of docs/plans/ for design intent.
# Task plans in docs/plans/*-plan.md are unchanged.
if [ -n "$_preset_name" ] && [ "$_preset_name" != "null" ] && [ -f "$_preset_file" ]; then
  _openspec_first="$(jq -r '.openspec_first // false' "$_preset_file" 2>/dev/null)"
  if [ "$_openspec_first" = "true" ]; then
    # Mutate phase_compositions in DEFAULT_JSON. DEFAULT_JSON is the source
    # for Step 8's phase_compositions extraction, so mutating here propagates
    # to the cache via PHASE_COMPOSITIONS.
    DEFAULT_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq '
      (.phase_compositions.DESIGN.hints // []) |= map(
        if (.text // "" | test("PERSIST DESIGN")) then
          .text = "PERSIST DESIGN (spec-driven): Create `openspec/changes/<feature-slug>/proposal.md`, `openspec/changes/<feature-slug>/design.md`, and `openspec/changes/<feature-slug>/specs/<capability-slug>/spec.md` upfront after brainstorming approval. Sections in proposal: Why, What Changes, Capabilities (Added/Modified), Impact. Sections in design: Architecture, Trade-offs, Dissenting views, Decisions. Spec file uses RFC 2119 UPPERCASE keywords and 2-4 GIVEN/WHEN/THEN acceptance scenarios. Then run: source hooks/lib/openspec-state.sh && openspec_state_upsert_change \"$TOKEN\" \"$SLUG\" \"\" \"\" \"$CAPABILITY_SLUG\" \"\" to set change_slug + capability_slug in session state. If introducing a new capability, emit a visible NEW CAPABILITY warning for user review."
        elif (.text // "" | test("DESIGN.PLAN CONTRACT")) then
          .text = "DESIGN\u2192PLAN CONTRACT (spec-driven): Before transitioning from DESIGN to PLAN, the `openspec/changes/<feature-slug>/` folder MUST contain: (1) proposal.md with Capabilities section listing every subsystem touched, (2) design.md with Architecture and explicit out-of-scope, (3) specs/<capability-slug>/spec.md with 2-4 GIVEN/WHEN/THEN acceptance scenarios. These files are COMMITTED so teammates see in-progress design intent via git."
        else . end
      ) |
      (.phase_compositions.PLAN.hints // []) |= map(
        if (.text // "" | test("CARRY SCENARIOS")) then
          .text = "CARRY SCENARIOS (spec-driven): Read acceptance scenarios from `openspec/changes/<feature-slug>/specs/<capability-slug>/spec.md` and carry them into the plan as verification criteria. Save the plan to `docs/plans/YYYY-MM-DD-<slug>-plan.md` (local task breakdown, gitignored)."
        else . end
      )
    ')"
    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg m "spec-driven mode active: design intent persisted to openspec/changes/ (committed)" '. + [$m]')"

    # Discovery nudge: if the consumer repo is missing the OpenSpec Validate
    # workflow, spec-driven mode has no CI enforcement. Emit a one-line hint
    # pointing at /setup so the installer can fix it.
    # SKILL_TARGET_REPO override lets tests point this at a clean tempdir.
    _target_repo="${SKILL_TARGET_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
    if [ ! -f "${_target_repo}/.github/workflows/openspec-validate.yml" ]; then
      WARNINGS="$(printf '%s' "${WARNINGS}" | jq --arg m "spec-driven mode active but no OpenSpec Validate workflow found at .github/workflows/openspec-validate.yml — run /setup to install the CI gate, or copy .github/workflows/openspec-validate.yml and scripts/validate-active-openspec-changes.sh from the auto-claude-skills plugin repo. See docs/CI.md for branch-protection setup." '. + [$m]')"
    fi
  fi
fi

if [ -f "${USER_CONFIG}" ] && jq empty "${USER_CONFIG}" >/dev/null 2>&1; then
    USER_CONFIG_JSON="$(cat "${USER_CONFIG}")"
    SKILLS_JSON="$(printf '%s' "${SKILLS_JSON}" | jq --argjson cfg "$(printf '%s' "${USER_CONFIG_JSON}")" '
        # Process overrides
        ($cfg.overrides // {}) as $overrides |
        [.[] | . as $skill |
            if $overrides[$skill.name] then
                ($overrides[$skill.name]) as $ovr |
                (if $ovr | has("enabled") then {enabled: $ovr.enabled} else {} end) as $enable |
                (if $ovr.triggers then
                    ($ovr.triggers | map(select(startswith("+"))) | map(ltrimstr("+"))) as $add |
                    ($ovr.triggers | map(select(startswith("-"))) | map(ltrimstr("-"))) as $rem |
                    ($ovr.triggers | map(select((startswith("+") or startswith("-")) | not))) as $replace |
                    if ($replace | length) > 0 then {triggers: $replace}
                    else {triggers: ((.triggers + $add) | [.[] | select(. as $t | $rem | any(. == $t) | not)])}
                    end
                else {} end) as $trigs |
                . + $enable + $trigs
            else . end
        ] +
        [($cfg.custom_skills // [])[] | . + {available: true, enabled: true}]
    ')"
fi

# -----------------------------------------------------------------
# Step 8: Extract methodology_hints from default-triggers.json
# -----------------------------------------------------------------
if [ -n "${DEFAULT_JSON}" ]; then
    _meta="$(printf '%s' "${DEFAULT_JSON}" | jq -r -j '
        (.methodology_hints // [] | tojson),
        "\u001f",
        (.phase_compositions // {} | tojson),
        "\u001f",
        (.phase_guide // {} | tojson)
    ')"
    METHODOLOGY_HINTS="${_meta%%$'\x1f'*}"; _meta="${_meta#*$'\x1f'}"
    PHASE_COMPOSITIONS="${_meta%%$'\x1f'*}"
    PHASE_GUIDE="${_meta#*$'\x1f'}"
else
    METHODOLOGY_HINTS="[]"
    PHASE_COMPOSITIONS="{}"
    PHASE_GUIDE="{}"
fi

# -----------------------------------------------------------------
# Step 8b: Discover curated plugins from default-triggers.json
# -----------------------------------------------------------------
PLUGINS_JSON="[]"
if [ -n "${DEFAULT_JSON}" ]; then
    # 1) Get all curated plugin names in one jq call
    _curated_names="$(printf '%s' "${DEFAULT_JSON}" | jq -r '.plugins // [] | .[].name')"

    # 2) Check installation bash-side — iterate names, check dirs
    _installed_names=""
    while IFS= read -r _cn; do
        [ -z "${_cn}" ] && continue
        for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
            [ -d "${_mkt_dir}" ] || continue
            if [ -d "${_mkt_dir}${_cn}" ]; then
                _installed_names="${_installed_names}${_cn}
"
                break
            fi
        done
    done <<CURATED_EOF
${_curated_names}
CURATED_EOF

    # 3) Single jq call — produce full PLUGINS_JSON with available flag
    PLUGINS_JSON="$(printf '%s' "${DEFAULT_JSON}" | jq --arg installed "${_installed_names}" '
        ($installed | split("\n") | map(select(. != ""))) as $inst |
        [.plugins // [] | .[] | .name as $n | . + {available: ([$inst[] | select(. == $n)] | length > 0)}]
    ')"
fi

# -----------------------------------------------------------------
# Step 8c: Auto-discover plugin metadata from all marketplaces
# -----------------------------------------------------------------
# Build exclusion list: curated plugins (already in PLUGINS_JSON) + self
# External plugins discovered by the unified scanner are NOT excluded here
# because Step 8c collects plugin-level metadata (commands, agents, hooks)
# that the skill scanner does not capture.
CURATED_NAMES="$(printf '%s' "${PLUGINS_JSON}" | jq -r '.[].name' 2>/dev/null)"
KNOWN_NAMES="${CURATED_NAMES}
auto-claude-skills"

# Collect plugin metadata (commands, agents) bash-side, then merge in one jq call
_DISCOVERED_ENTRIES=""
_ENTRY_DELIM="@@ENTRY@@"
_FIELD_DELIM="@@F@@"

for _mkt_dir in "${HOME}/.claude/plugins/cache"/*/; do
    [ -d "${_mkt_dir}" ] || continue
    for _plugin_dir in "${_mkt_dir}"*/; do
        [ -d "${_plugin_dir}" ] || continue
        _pname="$(basename "${_plugin_dir}")"

        # Skip known/curated/already-discovered plugins
        _skip=0
        while IFS= read -r _kn; do
            [ -z "${_kn}" ] && continue
            if [ "${_kn}" = "${_pname}" ]; then
                _skip=1
                break
            fi
        done <<KNEOF
${KNOWN_NAMES}
KNEOF
        [ "${_skip}" -eq 1 ] && continue

        # Look for plugin.json — may be directly in plugin dir or in a version subdir
        _pjson=""
        _plugin_root=""
        if [ -f "${_plugin_dir}.claude-plugin/plugin.json" ]; then
            _pjson="${_plugin_dir}.claude-plugin/plugin.json"
            _plugin_root="${_plugin_dir}"
        else
            for _vdir in "${_plugin_dir}"*/; do
                [ -d "${_vdir}" ] || continue
                if [ -f "${_vdir}.claude-plugin/plugin.json" ]; then
                    _pjson="${_vdir}.claude-plugin/plugin.json"
                    _plugin_root="${_vdir}"
                    break
                fi
            done
        fi
        [ -z "${_pjson}" ] && continue

        # Collect skill names as newline-separated string (no jq per item)
        _skill_names=""
        if [ -d "${_plugin_root}skills" ]; then
            for _smd in "${_plugin_root}skills"/*/SKILL.md; do
                [ -f "${_smd}" ] || continue
                _skill_names="${_skill_names}$(basename "$(dirname "${_smd}")")
"
            done
        fi

        # Collect command names with "/" prefix bash-side (no jq per item)
        _cmd_names=""
        if [ -d "${_plugin_root}commands" ]; then
            for _cmd in "${_plugin_root}commands"/*.md; do
                [ -f "${_cmd}" ] || continue
                _cmd_names="${_cmd_names}/$(basename "${_cmd}" .md)
"
            done
        fi

        # Collect agent names as newline-separated string (no jq per item)
        _agent_names=""
        if [ -d "${_plugin_root}agents" ]; then
            for _agent in "${_plugin_root}agents"/*.md; do
                [ -f "${_agent}" ] || continue
                _agent_names="${_agent_names}$(basename "${_agent}" .md)
"
            done
        fi

        # Accumulate entry as delimited string (no jq fork)
        _DISCOVERED_ENTRIES="${_DISCOVERED_ENTRIES}${_DISCOVERED_ENTRIES:+${_ENTRY_DELIM}}${_pname}${_FIELD_DELIM}${_skill_names}${_FIELD_DELIM}${_cmd_names}${_FIELD_DELIM}${_agent_names}"
    done
done

# Single jq call to merge all discovered plugins into PLUGINS_JSON
if [ -n "${_DISCOVERED_ENTRIES}" ]; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq \
        --arg entries "${_DISCOVERED_ENTRIES}" \
        --arg edelim "${_ENTRY_DELIM}" \
        --arg fdelim "${_FIELD_DELIM}" \
        '. + [
            $entries | split($edelim)[] |
            split($fdelim) as $f |
            {
                name: $f[0],
                source: "auto-discovered",
                provides: {
                    commands: ($f[2] | split("\n") | map(select(. != ""))),
                    skills:  ($f[1] | split("\n") | map(select(. != ""))),
                    agents:  ($f[3] | split("\n") | map(select(. != ""))),
                    hooks: []
                },
                phase_fit: ["*"],
                description: "Auto-discovered plugin",
                available: true
            }
        ]')"
fi

# -----------------------------------------------------------------
# Step 8d: Detect context stack capabilities
# -----------------------------------------------------------------
# Check which tools in the Unified Context Stack are available.
# Results written to registry as context_capabilities object.

# Context Hub CLI: check PATH (bash-side, before single jq call)
_has_chub_cli=false
if command -v chub >/dev/null 2>&1; then
    _has_chub_cli=true
fi

# OpenSpec CLI: check PATH
_has_openspec=false
if command -v openspec >/dev/null 2>&1; then
    _has_openspec=true
fi

# LSP capability: requires BOTH an installed LSP plugin AND a resolvable backing binary.
# Claude Code's LSP plugin family (typescript-lsp, pyright-lsp, gopls-lsp, rust-analyzer-lsp,
# jdtls-lsp, clangd-lsp, csharp-lsp, kotlin-lsp, lua-lsp, php-lsp, ruby-lsp, swift-lsp, ...)
# each declare `lspServers.<name>.command` in their plugin.json pointing at an external
# language-server binary (e.g. `typescript-language-server`, installed via npm). The plugin
# can be present without its backing binary (user installed the plugin but not the server),
# in which case mcp__ide__getDiagnostics would fail at runtime. Flipping lsp=true only when
# at least one command is resolvable prevents false-positive guidance.
#
# Also captures plugin-present-binary-missing pairs so the hook can emit a "partial LSP
# install" diagnostic at session-start telling the user exactly which binary to install.
_has_lsp_plugin=false
_lsp_partial=""   # "<plugin-name>|<missing-cmd-csv>" entries, newline-separated
for _pjson in "${HOME}/.claude/plugins/cache"/*/*/.claude-plugin/plugin.json \
              "${HOME}/.claude/plugins/cache"/*/*/*/.claude-plugin/plugin.json; do
    [ -f "${_pjson}" ] || continue
    # Extract non-null .lspServers.*.command values, newline-separated (empty if no lspServers).
    _lsp_cmds="$(jq -r '(.lspServers // {}) | to_entries[] | .value.command // empty' "${_pjson}" 2>/dev/null)"
    [ -z "${_lsp_cmds}" ] && continue
    _plugin_name="$(jq -r '.name // "unknown"' "${_pjson}" 2>/dev/null)"
    _missing_for_plugin=""
    _any_resolved=0
    while IFS= read -r _cmd; do
        [ -z "${_cmd}" ] && continue
        if command -v "${_cmd}" >/dev/null 2>&1; then
            _any_resolved=1
            _has_lsp_plugin=true
        else
            _missing_for_plugin="${_missing_for_plugin}${_missing_for_plugin:+,}${_cmd}"
        fi
    done <<LSPEOF
${_lsp_cmds}
LSPEOF
    if [ "${_any_resolved}" -eq 0 ] && [ -n "${_missing_for_plugin}" ]; then
        _lsp_partial="${_lsp_partial}${_lsp_partial:+
}${_plugin_name}|${_missing_for_plugin}"
    fi
done

# -----------------------------------------------------------------
# Step 8e: Detect OpenSpec capabilities (workspace commands + surface)
# -----------------------------------------------------------------
_WORKSPACE_ROOT="${_OPENSPEC_WORKSPACE_OVERRIDE:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
_opsx_cmds=""
if [ -d "${_WORKSPACE_ROOT}/.claude/commands/opsx" ]; then
    for _cmd in "${_WORKSPACE_ROOT}/.claude/commands/opsx"/*.md; do
        [ -f "${_cmd}" ] || continue
        _opsx_cmds="${_opsx_cmds}${_opsx_cmds:+,}/opsx:$(basename "${_cmd}" .md)"
    done
fi

# Build OPENSPEC_CAPS JSON: binary + commands + surface + warnings
# Single jq call derives surface from command set
OPENSPEC_CAPS="$(jq -n \
    --argjson binary "${_has_openspec}" \
    --arg cmds "${_opsx_cmds}" \
    '($cmds | split(",") | map(select(. != ""))) as $commands |
    ($commands | map(split(":")[1]) | map(select(. != null))) as $names |
    (($names | index("propose") != null) and ($names | index("apply") != null) and ($names | index("archive") != null)) as $has_core |
    (($names | index("new") != null) or ($names | index("ff") != null) or ($names | index("continue") != null) or ($names | index("verify") != null) or ($names | index("sync") != null)) as $has_expanded |
    (if $binary and $has_core and $has_expanded then "opsx-expanded"
     elif $binary and $has_core then "opsx-core"
     elif $binary then "openspec-core"
     else "none" end) as $surface |
    (if ($binary | not) and ($commands | length) > 0 then ["OPSX command files found but openspec binary missing"]
     else [] end) as $warnings |
    {binary: $binary, commands: $commands, surface: $surface, warnings: $warnings}'
)"

# Canonical context_capabilities keys. Single source of truth consumed by:
# 1. CONTEXT_CAPS producer below (initial detection object)
# 2. User-config override filter (drops any non-canonical key from skill-config.json)
# 3. Fallback-registry writer (Step 10c, hardcoded jq — kept in sync via comment)
# If you add a capability, update this array AND the fallback writer's jq expression.
_CANONICAL_CAP_KEYS='["context7","context_hub_cli","context_hub_available","serena","forgetful_memory","openspec","posthog","lsp"]'

# Single jq call: detect all plugin capabilities, derive bindings, build CONTEXT_CAPS
# (Context7 detection checks plugin name, not MCP tool names. Covers the standard
# install path via claude-plugins-official. If Context7 were ever provided by a
# differently-named plugin, this would need MCP tool detection instead.)
CONTEXT_CAPS="$(printf '%s' "${PLUGINS_JSON}" | jq \
    --argjson chub "${_has_chub_cli}" \
    --argjson openspec "${_has_openspec}" \
    --argjson lsp "${_has_lsp_plugin}" \
    '[.[] | select(.available == true) | .name] as $avail |
    ($avail | index("context7") != null) as $c7 |
    ($avail | index("serena") != null) as $ser |
    ($avail | index("forgetful") != null) as $fm |
    ($avail | index("posthog") != null) as $ph |
    {context7:$c7, context_hub_cli:$chub, context_hub_available:$c7, serena:$ser, forgetful_memory:$fm, openspec:$openspec, posthog:$ph, lsp:$lsp}'
)"

# MCP fallback: check ~/.claude.json for servers not detected via plugins
_CLAUDE_JSON="${HOME}/.claude.json"
if [ -f "${_CLAUDE_JSON}" ] && command -v jq >/dev/null 2>&1; then
    CONTEXT_CAPS="$(printf '%s' "${CONTEXT_CAPS}" | jq \
        --slurpfile cj "${_CLAUDE_JSON}" \
        --arg proj "${_WORKSPACE_ROOT}" \
        '# Check user-scoped mcpServers
         ($cj[0].mcpServers // {}) as $user_mcp |
         # Check project-scoped mcpServers
         (($cj[0].projects[$proj].mcpServers // {}) ) as $proj_mcp |
         # Merge: project overrides user
         ($user_mcp + $proj_mcp) as $all_mcp |
         # Augment: only upgrade false->true, never downgrade
         if .serena == false and ($all_mcp | has("serena")) then .serena = true else . end |
         if .forgetful_memory == false and ($all_mcp | has("forgetful")) then .forgetful_memory = true else . end |
         if .context7 == false and ($all_mcp | has("context7")) then .context7 = true else . end |
         if .posthog == false and ($all_mcp | has("posthog")) then .posthog = true else . end'
    )" || true
fi
# Note: no MCP fallback for lsp. Claude Code's LSP family uses the `lspServers` plugin-manifest
# primitive, not MCP servers, and is detected earlier via the `_has_lsp_plugin` scan with a
# mandatory `command -v` check. An `ide` MCP entry in ~/.claude.json would not guarantee a
# working language server on PATH, so flipping lsp=true on that signal alone would re-introduce
# the false-positive the plugin+binary contract is designed to prevent. Users who need to force
# lsp=true can use `skill-config.json` `context_capabilities.lsp: true`.

# User-config override: skill-config.json may force context_capabilities on.
# Augment-only: only upgrades false->true, never downgrades — matches MCP fallback pattern.
# Whitelist-filtered: only canonical capability keys are honored; arbitrary keys are dropped.
# This prevents users from injecting non-capability flags that would then leak into
# any iterator-based consumer of context_capabilities (e.g. health-check summaries).
if [ -f "${USER_CONFIG}" ] && jq empty "${USER_CONFIG}" >/dev/null 2>&1; then
    CONTEXT_CAPS="$(printf '%s' "${CONTEXT_CAPS}" | jq \
        --slurpfile uc "${USER_CONFIG}" \
        --argjson allowed "${_CANONICAL_CAP_KEYS}" \
        '($uc[0].context_capabilities // {}) as $ovr |
         reduce ($ovr | to_entries[] | select(.key as $k | $allowed | index($k))) as $e (.;
             if ($e.value == true) and (.[$e.key] == false or .[$e.key] == null)
             then .[$e.key] = true
             else . end)'
    )" || true
fi

# Override unified-context-stack plugin available flag when any capability is present
if printf '%s' "${CONTEXT_CAPS}" | jq -e 'to_entries | any(.value == true)' >/dev/null 2>&1; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "unified-context-stack" then .available = true else . end)
    ')"
fi

# Set PostHog plugin available flag when MCP server is detected
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.posthog == true' >/dev/null 2>&1; then
    PLUGINS_JSON="$(printf '%s' "${PLUGINS_JSON}" | jq '
        map(if .name == "posthog" then .available = true else . end)
    ')"
fi

# ── Step 8f: Detect security scanner capabilities ──────────────────
_SEMGREP=false; _OPENGREP=false; _TRIVY=false; _GITLEAKS=false
command -v semgrep  >/dev/null 2>&1 && _SEMGREP=true
command -v opengrep >/dev/null 2>&1 && _OPENGREP=true
command -v trivy    >/dev/null 2>&1 && _TRIVY=true
command -v gitleaks >/dev/null 2>&1 && _GITLEAKS=true
SECURITY_CAPS="semgrep=${_SEMGREP}, opengrep=${_OPENGREP}, trivy=${_TRIVY}, gitleaks=${_GITLEAKS}"

# ── Step 8g: Detect observability capabilities ──────────────────────
_OBS_GCLOUD=false; _OBS_MCP=false; _OBS_KUBECTL=false
command -v gcloud >/dev/null 2>&1 && _OBS_GCLOUD=true
command -v kubectl >/dev/null 2>&1 && _OBS_KUBECTL=true
# Check if GCP Observability MCP is configured in ~/.claude.json
if [ -f "${HOME}/.claude.json" ]; then
    jq -e '.mcpServers["gcp-observability"] // .mcpServers["observability"]' "${HOME}/.claude.json" >/dev/null 2>&1 && _OBS_MCP=true
fi

# -----------------------------------------------------------------
# Step 9+10: Build final registry JSON, extract stats, and cache
# -----------------------------------------------------------------
RESULT="$(jq -n \
    --arg version "4.0.0" \
    --arg fm_version "1" \
    --argjson skills "${SKILLS_JSON}" \
    --argjson plugins "${PLUGINS_JSON}" \
    --argjson caps "${CONTEXT_CAPS}" \
    --argjson openspec_caps "${OPENSPEC_CAPS}" \
    --argjson pc "${PHASE_COMPOSITIONS}" \
    --argjson pg "${PHASE_GUIDE}" \
    --argjson mh "${METHODOLOGY_HINTS}" \
    --argjson warnings "${WARNINGS}" \
    '{
        registry: {version:$version, frontmatter_schema_version: ($fm_version | tonumber), skills:$skills, plugins:$plugins, context_capabilities:$caps,
                   openspec_capabilities:$openspec_caps,
                   phase_compositions:$pc, phase_guide:$pg,
                   methodology_hints:$mh, warnings:$warnings},
        stats: {
            skill_count: ($skills | length),
            available: ([$skills[] | select(.available)] | length),
            warning_count: ($warnings | length),
            plugin_count: ($plugins | length),
            plugin_available: ([$plugins[] | select(.available)] | length)
        }
    }')"

# -----------------------------------------------------------------
# Step 10b: Reconcile against previous registry
# -----------------------------------------------------------------
RECONCILIATION_WARNINGS="[]"

if [ -f "${CACHE_FILE}" ]; then
    RECONCILIATION_WARNINGS="$(jq -n \
        --slurpfile prev "${CACHE_FILE}" \
        --argjson curr "${SKILLS_JSON}" \
        --argjson user_cfg "$([ -f "${USER_CONFIG}" ] && cat "${USER_CONFIG}" 2>/dev/null || echo '{}')" \
        --argjson phase_comp "${PHASE_COMPOSITIONS}" \
        '
        # Compute previous and current skill name sets
        ([$prev[0].skills // [] | .[].name] | sort | unique) as $prev_names |
        ([$curr[] | .name] | sort | unique) as $curr_names |

        # Added and removed skills
        ([$curr_names[] | select(. as $n | $prev_names | index($n) | not)] |
            map("+ " + . + " (newly discovered)")) as $added |
        ([$prev_names[] | select(. as $n | $curr_names | index($n) | not)] |
            map("- " + . + " (removed)")) as $removed |

        # Orphaned user config overrides
        (($user_cfg.overrides // {}) | keys) as $override_names |
        ([$override_names[] | select(. as $n | $curr_names | index($n) | not)] |
            map("orphan: override for \"" + . + "\" no longer matches any installed skill")) as $orphans |

        # Rename detection: >=50% word overlap on description, same removed+added set
        ([$prev[0].skills // [] | .[] | {(.name): (.description // "")}] | add // {}) as $prev_desc |
        ([$curr[] | {(.name): (.description // "")}] | add // {}) as $curr_desc |
        ([$removed[] | ltrimstr("- ") | split(" (")[0]]) as $rem_names |
        ([$added[] | ltrimstr("+ ") | split(" (")[0]]) as $add_names |
        ([($rem_names[]) as $old | ($add_names[]) as $new |
          (($prev_desc[$old] // "") | ascii_downcase | split(" ") | map(select(length > 2))) as $old_words |
          (($curr_desc[$new] // "") | ascii_downcase | split(" ") | map(select(length > 2))) as $new_words |
          ([($old_words | length), ($new_words | length)] | max) as $max_len |
          select($max_len > 0) |
          ([$old_words[] | select(. as $w | $new_words | index($w) != null)] | length) as $overlap |
          select(($overlap / $max_len) >= 0.5) |
          "rename: possible rename " + $old + " \u2192 " + $new
        ] | unique) as $renames |

        # Phase composition resilience: warn about stale references to removed skills
        ([$phase_comp | .. | strings] | unique) as $comp_refs |
        ([$rem_names[] | select(. as $n | $comp_refs | index($n) != null)] |
            map("stale-ref: phase composition references removed skill \"" + . + "\"")) as $stale_refs |

        ($added + $removed + $orphans + $renames + $stale_refs)
    ')" || RECONCILIATION_WARNINGS="[]"
fi

if [ "${RECONCILIATION_WARNINGS}" != "[]" ]; then
    WARNINGS="$(printf '%s' "${WARNINGS}" | jq --argjson rw "${RECONCILIATION_WARNINGS}" '. + $rw')"
    # Update RESULT with new warnings
    RESULT="$(printf '%s' "${RESULT}" | jq --argjson w "${WARNINGS}" '.registry.warnings = $w')"
fi

# Write registry to cache (strip the stats wrapper)
printf '%s' "${RESULT}" | jq '.registry' > "${CACHE_FILE}.tmp.$$" && mv "${CACHE_FILE}.tmp.$$" "${CACHE_FILE}"

# -----------------------------------------------------------------
# Step 10c: Auto-regenerate fallback registry (canonical shape only)
# -----------------------------------------------------------------
# The committed fallback is built from default-triggers.json (curated source
# of truth) with every .available and every context_capabilities value zeroed.
# It intentionally excludes auto-discovered plugins, user-installed skills,
# and the writer's machine state — it exists to give the no-jq path a
# structurally valid registry, not a snapshot of any particular machine.
# Runtime cache (CACHE_FILE) keeps the machine-accurate flags for routing.
_FALLBACK="${PLUGIN_ROOT}/config/fallback-registry.json"
if [ -d "${PLUGIN_ROOT}/config" ] && [ -z "${_SKILL_TEST_MODE:-}" ] && [ -n "${DEFAULT_JSON_PRISTINE}" ]; then
    # Build fallback from pristine default-triggers.json only.
    # No user-config, no presets, no auto-discovery, no RESULT — pure curated shape.
    # Canonical context_capabilities keys come from _CANONICAL_CAP_KEYS (single source
    # of truth defined near the CONTEXT_CAPS producer above).
    _new_fallback="$(printf '%s' "${DEFAULT_JSON_PRISTINE}" | jq \
        --argjson cap_keys "${_CANONICAL_CAP_KEYS}" \
        '. as $d |
        {
            version: ($d.version // "4.0.0-fallback"),
            frontmatter_schema_version: 1,
            skills: [($d.skills // [])[] | . + {available: false, enabled: (.enabled // true)}],
            plugins: [($d.plugins // [])[] | . + {available: false}],
            context_capabilities: ($cap_keys | map({(.): false}) | add),
            openspec_capabilities: {binary: false, commands: [], surface: "none", warnings: []},
            phase_compositions: ($d.phase_compositions // {}),
            phase_guide: ($d.phase_guide // {}),
            methodology_hints: ($d.methodology_hints // []),
            warnings: []
        }
    ')"
    if [ -f "${_FALLBACK}" ]; then
        _existing="$(cat "${_FALLBACK}" 2>/dev/null)"
        if [ "${_new_fallback}" != "${_existing}" ]; then
            printf '%s\n' "${_new_fallback}" > "${_FALLBACK}.tmp.$$" 2>/dev/null && mv "${_FALLBACK}.tmp.$$" "${_FALLBACK}" 2>/dev/null || {
                [ -n "${SKILL_EXPLAIN:-}" ] && printf '[session-start] fallback-registry write skipped: read-only PLUGIN_ROOT\n' >&2
            }
        fi
    else
        printf '%s\n' "${_new_fallback}" > "${_FALLBACK}.tmp.$$" 2>/dev/null && mv "${_FALLBACK}.tmp.$$" "${_FALLBACK}" 2>/dev/null || {
            [ -n "${SKILL_EXPLAIN:-}" ] && printf '[session-start] fallback-registry write skipped: read-only PLUGIN_ROOT\n' >&2
        }
    fi
fi

# Extract stats for health message
read -r SKILL_COUNT AVAILABLE_COUNT WARNING_COUNT PLUGIN_COUNT PLUGIN_AVAILABLE <<EOF
$(printf '%s' "${RESULT}" | jq -r '.stats | "\(.skill_count) \(.available) \(.warning_count) \(.plugin_count) \(.plugin_available)"')
EOF
UNAVAILABLE_COUNT=$((SKILL_COUNT - AVAILABLE_COUNT))

# -----------------------------------------------------------------
# Step 11: Detect missing companion plugins, MCPs, skills, and features
# -----------------------------------------------------------------

# Helper: check if a plugin is installed in any marketplace cache
_plugin_installed() {
    local _name="$1"
    case "${_name}" in
        superpowers)
            [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/superpowers" ] || \
            [ -d "${HOME}/.claude/plugins/cache/superpowers-marketplace/superpowers" ]
            ;;
        *)
            [ -d "${HOME}/.claude/plugins/cache/claude-plugins-official/${_name}" ]
            ;;
    esac
}

# Core plugins (essential for the SDLC loop)
MISSING_CORE=""
MISSING_CORE_COUNT=0
for _plugin in superpowers frontend-design claude-md-management claude-code-setup pr-review-toolkit; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_CORE="${MISSING_CORE:+${MISSING_CORE}, }${_plugin}"
        MISSING_CORE_COUNT=$((MISSING_CORE_COUNT + 1))
    fi
done

# MCP plugins (SDLC data sources — live docs, GitHub, Atlassian)
# Note: Atlassian may be available as a claude.ai managed integration
# (mcp__claude_ai_Atlassian__) without a marketplace install.
MISSING_MCP=""
MISSING_MCP_COUNT=0
for _plugin in context7 github; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_MCP="${MISSING_MCP:+${MISSING_MCP}, }${_plugin}"
        MISSING_MCP_COUNT=$((MISSING_MCP_COUNT + 1))
    fi
done

# Phase enhancer plugins (improve specific SDLC phases)
MISSING_ENHANCERS=""
MISSING_ENHANCERS_COUNT=0
for _plugin in commit-commands security-guidance feature-dev hookify skill-creator; do
    if ! _plugin_installed "${_plugin}"; then
        MISSING_ENHANCERS="${MISSING_ENHANCERS:+${MISSING_ENHANCERS}, }${_plugin}"
        MISSING_ENHANCERS_COUNT=$((MISSING_ENHANCERS_COUNT + 1))
    fi
done

# Recommended skills (external)
MISSING_SKILLS=""
MISSING_SKILLS_COUNT=0
for _skill in doc-coauthoring webapp-testing; do
    if [ ! -f "${HOME}/.claude/skills/${_skill}/SKILL.md" ]; then
        MISSING_SKILLS="${MISSING_SKILLS:+${MISSING_SKILLS}, }${_skill}"
        MISSING_SKILLS_COUNT=$((MISSING_SKILLS_COUNT + 1))
    fi
done

# Check agent teams
AGENT_TEAMS_MISSING=0
if [ -f "${HOME}/.claude/settings.json" ]; then
    _at_val="$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // ""' "${HOME}/.claude/settings.json" 2>/dev/null)"
    [ "${_at_val}" != "1" ] && AGENT_TEAMS_MISSING=1
else
    AGENT_TEAMS_MISSING=1
fi

# Count total and installed companion plugins (core + MCP + enhancers)
TOTAL_COMPANIONS=12  # 5 core + 2 MCP + 5 enhancers
MISSING_COMPANION_COUNT=$((MISSING_CORE_COUNT + MISSING_MCP_COUNT + MISSING_ENHANCERS_COUNT))
INSTALLED_COMPANIONS=$((TOTAL_COMPANIONS - MISSING_COMPANION_COUNT))

# Count missing context stack tools
MISSING_CONTEXT_COUNT=$(printf '%s' "${CONTEXT_CAPS}" | jq '[to_entries[] | select(.value == false)] | length')

# -----------------------------------------------------------------
# Step 12: Emit health check
# -----------------------------------------------------------------
SETUP_CTA=""
if [ "${MISSING_COMPANION_COUNT}" -gt 0 ] || [ "${MISSING_SKILLS_COUNT}" -gt 0 ] || \
   [ "${AGENT_TEAMS_MISSING}" -eq 1 ] || [ "${MISSING_CONTEXT_COUNT}" -gt 0 ]; then
    SETUP_CTA=". Run /setup for the full experience"
else
    SETUP_CTA=". Setup complete"
fi
_ZM_STAT=""
if [[ "$_PREV_TOTAL" -gt 10 ]] && [[ "$_PREV_ZM" -gt 0 ]]; then
    _ZM_STAT=" | prev: ${_PREV_ZM}/${_PREV_TOTAL} unmatched"
fi
STATUS="SessionStart: ${AVAILABLE_COUNT} skills active (${INSTALLED_COMPANIONS} of ${TOTAL_COMPANIONS} plugins)${_ZM_STAT}${SETUP_CTA}"

# Build model context: status + first-response instruction + any warnings
CONTEXT="${STATUS}
MANDATORY: Before any other output, report the skill system status to the user in one line (e.g. '24 skills active across 7 plugins — run /setup to complete installation'). Do not skip or defer this."

# Append context capabilities summary for model consumption
# CONTEXT_CAPS is always set on the jq-available path (jq-unavailable exits at step 2)
_CAP_LINE="$(printf '%s' "${CONTEXT_CAPS}" | jq -r 'to_entries | map("\(.key)=\(.value)") | "Context Stack: " + join(", ")')"
if [ -n "${_CAP_LINE}" ]; then
    CONTEXT="${CONTEXT}
${_CAP_LINE}"
fi

# Emit Serena usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.serena == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping. When spawning subagents via the Task tool for code work, include 'Serena available — prefer find_symbol over Grep for symbol lookups' in their prompt so they inherit this guidance."
fi

# Emit LSP usage hint when available (complementary to Serena — LSP for diagnostics, Serena for symbol nav)
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.lsp == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
LSP: Use mcp__ide__getDiagnostics for compile/type errors before grepping. Complementary to Serena — LSP for diagnostics, Serena for symbol navigation and structural edits."
elif [ -n "${_lsp_partial}" ]; then
    # Plugin-present-binary-missing diagnostic — tell the user exactly what to install.
    # Emit once, listing every partial plugin and its missing command(s).
    _lsp_hint_body=""
    while IFS= read -r _entry; do
        [ -z "${_entry}" ] && continue
        _pname="${_entry%%|*}"
        _cmds="${_entry#*|}"
        _lsp_hint_body="${_lsp_hint_body}${_lsp_hint_body:+; }${_pname} needs ${_cmds}"
    done <<LSPHINTEOF
${_lsp_partial}
LSPHINTEOF
    CONTEXT="${CONTEXT}
LSP (partial install): ${_lsp_hint_body}. Install the backing language-server binary to enable lsp=true. See the plugin's README for the install command."
fi

# Emit Forgetful usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.forgetful_memory == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Forgetful: Use discover_forgetful_tools to list available memory operations, then execute_forgetful_tool to query or store architectural knowledge across sessions."
fi

# Append OpenSpec capabilities summary
_OPENSPEC_LINE="$(printf '%s' "${OPENSPEC_CAPS}" | jq -r '
    "OpenSpec: binary=\(.binary), surface=\(.surface), commands=\(.commands | join(","))"
')"
if [ -n "${_OPENSPEC_LINE}" ]; then
    CONTEXT="${CONTEXT}
${_OPENSPEC_LINE}"
fi

# Append security scanner capabilities (with setup hint if any are missing).
# Hint if no SAST (semgrep+opengrep interchangeable) or if trivy/gitleaks is missing.
_SEC_HINT=""
if [ "${_SEMGREP}" = "false" ] && [ "${_OPENGREP}" = "false" ]; then
    _SEC_HINT=" — run /setup to install missing tools"
elif [ "${_TRIVY}" = "false" ] || [ "${_GITLEAKS}" = "false" ]; then
    _SEC_HINT=" — run /setup to install missing tools"
fi
CONTEXT="${CONTEXT}
Security tools: ${SECURITY_CAPS}${_SEC_HINT}"
_OBS_HINT=""
if [ "${_OBS_GCLOUD}" = "true" ] && [ "${_OBS_MCP}" = "false" ]; then
    _OBS_HINT=" — run /setup to add GCP Observability MCP for Tier 1 trace correlation"
fi
CONTEXT="${CONTEXT}
Observability tools: gcloud=${_OBS_GCLOUD}, observability_mcp=${_OBS_MCP}, kubectl=${_OBS_KUBECTL}${_OBS_HINT}"

# Check for stale/missing memory consolidation marker
_PROJ_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
_PROJ_HASH="$(printf '%s' "${_PROJ_ROOT}" | shasum | cut -d' ' -f1)"
_CONSOL_MARKER="${HOME}/.claude/.context-stack-consolidated-${_PROJ_HASH}"
if [ -f "${_CONSOL_MARKER}" ]; then
    # Compare marker mtime with last git commit time
    _MARKER_TIME="$(stat -f %m "${_CONSOL_MARKER}" 2>/dev/null || stat -c %Y "${_CONSOL_MARKER}" 2>/dev/null || echo 0)"
    _LAST_COMMIT="$(git -C "${_PROJ_ROOT}" log -1 --format=%ct 2>/dev/null || echo 0)"
    if [ "${_MARKER_TIME}" -lt "${_LAST_COMMIT}" ]; then
        CONTEXT="${CONTEXT}
Context Stack: Previous session may have unconsolidated learnings. Consider reviewing recent changes."
    fi
else
    # No marker at all — only warn if there are git commits (not a brand-new repo)
    _COMMIT_COUNT="$(git -C "${_PROJ_ROOT}" rev-list --count HEAD 2>/dev/null || echo 0)"
    if [ "${_COMMIT_COUNT}" -gt 1 ]; then
        CONTEXT="${CONTEXT}
Context Stack: Previous session may have unconsolidated learnings. Consider reviewing recent changes."
    fi
fi

# Append phase document pointers for model navigation
CONTEXT="${CONTEXT}
Context guidance per phase: triage-and-plan.md | implementation.md | testing-and-debug.md | code-review.md | ship-and-learn.md (in skills/unified-context-stack/phases/)"

if [ "${WARNING_COUNT}" -gt 0 ]; then
    CONTEXT="${CONTEXT}
Warnings: $(printf '%s' "${WARNINGS}" | jq -r '.[]')"
fi

printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' \
    "$(printf '%s' "${CONTEXT}" | jq -Rs .)"

exit 0
