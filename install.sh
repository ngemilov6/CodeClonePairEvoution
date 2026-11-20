#!/usr/bin/env bash
# Install OmniCCG and build its bundled NiCad 6.2 into .venv.
# Needs python3, gcc, make, unzip, curl and OpenTxl 11 (txl) installed first.
set -euo pipefail
cd "$(dirname "$0")"

# OmniCCG, from vendor/OmniCCG-main.zip or else from Zenodo
if [ ! -d vendor/OmniCCG-main ]; then
    mkdir -p vendor
    [ -f vendor/OmniCCG-main.zip ] ||
        curl -fL -o vendor/OmniCCG-main.zip 'https://zenodo.org/records/18344305/files/OmniCCG-main.zip?download=1'
    unzip -q vendor/OmniCCG-main.zip -d vendor
fi
python3 -m venv .venv
.venv/bin/pip install --quiet --disable-pip-version-check -e vendor/OmniCCG-main/OmniCCG-CLI

# NiCad 6.2 needs four fixes to build and run with GCC 15 and OpenTxl 11
cd vendor/OmniCCG-main/OmniCCG-CLI/src/omniccg/tools/NiCad
chmod a+rx nicad6 nicad6cross cleanall fixfilenames splitclasses scripts/*  # 1. the zip has no execute bits
grep -q std=gnu17 tools/Makefile || sed -i 's/gcc /gcc -std=gnu17 /' tools/Makefile  # 2. GCC 15 defaults to C23
for f in tools/*.x txl/*.x; do [ -x "$f" ] || rm -f "$f"; done  # stale prebuilt binaries would skip the build
make -s -C tools
make -s -k -C txl > /dev/null 2>&1 || true  # 3. only the non-Java plugins fail; we need the Java ones
sed -i '/requires FreeTXL/,/exit 99/ s/^\([[:space:]]*\)exit 99/\1: # exit 99/' scripts/NiCadPair scripts/NiCadCross  # 4. accept OpenTxl 11

echo "Done. Run: ./run.sh <repo-dir>"
