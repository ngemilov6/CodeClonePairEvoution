#!/usr/bin/env bash
# Install OmniCCG and build its bundled NiCad 6.2 into .venv.
# Needs python3, gcc, make, unzip, curl, Java and OpenTxl 11 (txl) installed first.
set -euo pipefail
cd "$(dirname "$0")"

if command -v py >/dev/null 2>&1; then
    PYTHON="py"
    PYTHON_ARGS=(-3)
elif command -v python >/dev/null 2>&1; then
    PYTHON=python
    PYTHON_ARGS=()
elif command -v python3 >/dev/null 2>&1; then
    PYTHON=python3
    PYTHON_ARGS=()
else
    echo "install.sh: Python was not found. Install Python 3 and add it to PATH." >&2
    exit 1
fi

# OmniCCG, from vendor/OmniCCG-main.zip or else from Zenodo
if [ ! -d vendor/OmniCCG-main ]; then
    mkdir -p vendor
    [ -f vendor/OmniCCG-main.zip ] ||
        curl -fL -o vendor/OmniCCG-main.zip 'https://zenodo.org/records/18344305/files/OmniCCG-main.zip?download=1'
    unzip -q vendor/OmniCCG-main.zip -d vendor
fi
"$PYTHON" "${PYTHON_ARGS[@]}" -m venv .venv
if [ -x .venv/Scripts/python.exe ]; then
    VENV_PYTHON=.venv/Scripts/python.exe
else
    VENV_PYTHON=.venv/bin/python
fi
"$VENV_PYTHON" -m pip install --quiet --disable-pip-version-check -e vendor/OmniCCG-main/OmniCCG-CLI

# Rascal, for the pattern detection in patterns/
[ -f rascal-shell-stable.jar ] ||
    curl -fL -o rascal-shell-stable.jar https://update.rascal-mpl.org/console/rascal-shell-stable.jar

# NiCad 6.2 needs four fixes to build and run with GCC 15 and OpenTxl 11
cd vendor/OmniCCG-main/OmniCCG-CLI/src/omniccg/tools/NiCad
chmod a+rx nicad6 nicad6cross cleanall fixfilenames splitclasses scripts/*  # 1. the zip has no execute bits
grep -q std=gnu17 tools/Makefile || sed -i 's/gcc /gcc -std=gnu17 /' tools/Makefile  # 2. GCC 15 defaults to C23
for f in tools/*.x txl/*.x; do [ -x "$f" ] || rm -f "$f"; done  # stale prebuilt binaries would skip the build
make -s -C tools
make -s -k -C txl > /dev/null 2>&1 || true  # 3. only the non-Java plugins fail; we need the Java ones
sed -i '/requires FreeTXL/,/exit 99/ s/^\([[:space:]]*\)exit 99/\1: # exit 99/' scripts/NiCadPair scripts/NiCadCross  # 4. accept OpenTxl 11
sed -i "s/grep 10\\.\\[89\\]/grep -E 'FreeTXL|OpenTxl'/" scripts/NiCadPair scripts/NiCadCross  # OpenTxl 11+ version check

echo "Done. Run: ./run.sh <repo-dir>"
