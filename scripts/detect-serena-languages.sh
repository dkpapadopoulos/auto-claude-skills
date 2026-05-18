#!/usr/bin/env bash
# detect-serena-languages.sh — Emit a newline-separated list of Serena language
# names matching the project root + immediate children. Bash 3.2 compatible.
#
# Usage:
#   scripts/detect-serena-languages.sh [<project-root>]
#   Default <project-root>: current working directory
#
# Output:
#   One Serena language name per line, deduped, manifest-match-first ordering.
#   Empty stdout if nothing detected.
#   Exit code 0 always (fail-open).
#
# Language detection matrix:
#   typescript: package.json | tsconfig.json | *.ts | *.tsx | *.js | *.jsx
#   rust:       Cargo.toml | *.rs
#   go:         go.mod | *.go
#   python:     pyproject.toml | requirements.txt | setup.py | *.py
#   java:       pom.xml | build.gradle | *.java
#   kotlin:     build.gradle.kts | *.kt | *.kts
#   csharp:     *.csproj | *.sln | *.cs
#   ruby:       Gemfile | *.rb
#   swift:      Package.swift | *.swift
#   bash:       *.sh | *.bash  (only when no other lang detected)
#
# Manifest matches outrank bare-extension matches; if a manifest is present,
# the extension scan for that language is skipped (we already know).
set -u
trap 'exit 0' ERR

PROJECT_ROOT="${1:-$(pwd)}"
[ -d "${PROJECT_ROOT}" ] || exit 0

# Detected language collector (order-preserving, deduped).
_DETECTED=""

_add() {
    case "${_DETECTED}" in
        *"|$1|"*) return ;;
        *) _DETECTED="${_DETECTED}|$1|" ;;
    esac
}

# Manifest scan (root + immediate children; -maxdepth 2)
_has() {
    find "${PROJECT_ROOT}" -maxdepth 2 -name "$1" -type f -print -quit 2>/dev/null | grep -q .
}

_has 'package.json'      && _add typescript
_has 'tsconfig.json'     && _add typescript
_has 'Cargo.toml'        && _add rust
_has 'go.mod'            && _add go
_has 'pyproject.toml'    && _add python
_has 'requirements.txt'  && _add python
_has 'setup.py'          && _add python
_has 'pom.xml'           && _add java
_has 'build.gradle'      && _add java
_has 'build.gradle.kts'  && _add kotlin
_has '*.csproj'          && _add csharp
_has '*.sln'             && _add csharp
_has 'Gemfile'           && _add ruby
_has 'Package.swift'     && _add swift

# Bare-extension fallback for languages NOT already captured via manifest.
_scan_ext() {
    # $1 = serena lang, $2..$n = filename globs
    local lang="$1"; shift
    case "${_DETECTED}" in *"|${lang}|"*) return ;; esac
    local pat
    for pat in "$@"; do
        if find "${PROJECT_ROOT}" -maxdepth 3 -name "${pat}" -type f -print -quit 2>/dev/null | grep -q .; then
            _add "${lang}"
            return
        fi
    done
}

_scan_ext typescript '*.ts' '*.tsx' '*.js' '*.jsx'
_scan_ext rust       '*.rs'
_scan_ext go         '*.go'
_scan_ext python     '*.py'
_scan_ext java       '*.java'
_scan_ext kotlin     '*.kt' '*.kts'
_scan_ext csharp     '*.cs'
_scan_ext ruby       '*.rb'
_scan_ext swift      '*.swift'

# Bash fallback — only if nothing else was detected.
if [ -z "${_DETECTED}" ]; then
    _scan_ext bash '*.sh' '*.bash'
fi

# Emit one language per line, stripping the |…| sentinels.
printf '%s' "${_DETECTED}" | tr '|' '\n' | awk 'NF' | awk '!seen[$0]++'

exit 0
