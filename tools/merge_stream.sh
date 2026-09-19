#!/usr/bin/env bash
# Merge a parallel stream's branch (or worktree path) into the current branch, run tests.
#   tools/merge_stream.sh <branch-or-worktree-path> [--no-test]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$1"; shift || true
if [ -d "$src" ]; then branch="$(git -C "$src" rev-parse --abbrev-ref HEAD)"; else branch="$src"; fi
echo "[merge] merging $branch into $(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
cd "$ROOT"
git merge --no-ff --no-edit "$branch" || { echo "[merge] CONFLICTS:"; git diff --name-only --diff-filter=U; exit 1; }
if [ "${1:-}" != "--no-test" ]; then ./run.sh test 2>&1 | grep -E "RESULT|tests,|FAIL" | tail -5; fi
