#!/usr/bin/env bash
# validate-knowledge-bundle.sh — CI entry: validate the repo's .claude/knowledge bundle if present.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
DIR="${ROOT}/.claude/knowledge"
[ -d "${DIR}" ] || { echo "no .claude/knowledge bundle — skipping"; exit 0; }
exec bash "${ROOT}/scripts/knowledge-validate.sh" "${DIR}"
