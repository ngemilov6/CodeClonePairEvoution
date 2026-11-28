#!/usr/bin/env bash
# ./run.sh <repo-dir> [--out DIR] [--fixed-leaps N | --from-commit SHA] [--first N | --last N] [--first-parent] [--java-only]
#     Runs OmniCCG on the repository (saving ccg_data.xml in the results folder),
#     then the clone pattern detection, and opens the report in the browser.
# ./run.sh <repo-dir or results folder> --patterns-only [--out DIR]
#     Skips OmniCCG and reruns only the pattern detection on the saved ccg_data.xml.
set -eo pipefail
here=$(cd "$(dirname "$0")" && pwd)

patterns_only=false; args=()
for a in "$@"; do if [ "$a" = --patterns-only ]; then patterns_only=true; else args+=("$a"); fi; done
set -- "${args[@]}"
if [ -x "$here/.venv/Scripts/python.exe" ]; then
    venv_python="$here/.venv/Scripts/python.exe"
else
    venv_python="$here/.venv/bin/python"
fi
$patterns_only || "$venv_python" "$here/clone_evo.py" "$@"

# The results folder: --out DIR, or <repo-dir>/clone-results, or the folder given
out=${1%/}/clone-results
[ -f "$1/ccg_data.xml" ] && out=$1
for i in "${!args[@]}"; do [ "${args[i]}" = --out ] && out=${args[i+1]}; done
if [ ! -f "$out/ccg_data.xml" ]; then
    $patterns_only && { echo "run.sh: no ccg_data.xml in $out; run without --patterns-only first" >&2; exit 1; }
    exit 0  # OmniCCG found no clone genealogy
fi
out=$(realpath "$out")
echo
cd "$here/patterns" && java -jar "$here/rascal-shell-stable.jar" Patterns "$out" 2>&1 |
    grep -v -e '^\[INFO\]' -e '^WARNING' -e '^Job:' -e '^  - |'
xdg-open "$out/patterns.html" > /dev/null 2>&1 &
