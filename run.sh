#!/usr/bin/env bash
# ./run.sh <repo-dir> [--out DIR] [--fixed-leaps N | --from-commit SHA] [--first N | --last N]
# Runs OmniCCG on the repository, then the late propagation detection on its result.
set -eo pipefail
here=$(cd "$(dirname "$0")" && pwd)
"$here/.venv/bin/python" "$here/clone_evo.py" "$@"

# The results folder: --out DIR, or <repo-dir>/clone-results
out=${1%/}/clone-results
args=("$@"); for i in "${!args[@]}"; do [ "${args[i]}" = --out ] && out=${args[i+1]}; done
[ -f "$out/ccg_data.xml" ] || exit 0
out=$(realpath "$out")
echo
cd "$here/patterns" && java -jar "$here/rascal-shell-stable.jar" LatePropagation "$out" 2>&1 |
    grep -v -e '^\[INFO\]' -e '^WARNING' -e '^Job:' -e '^  - |'
