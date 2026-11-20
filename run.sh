#!/usr/bin/env bash
# ./run.sh <repo-dir> [--out DIR] [--fixed-leaps N | --from-commit SHA] [--first N | --last N]
here=$(dirname "$0")
exec "$here/.venv/bin/python" "$here/clone_evo.py" "$@"
