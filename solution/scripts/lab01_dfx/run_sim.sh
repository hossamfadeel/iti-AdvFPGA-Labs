#!/usr/bin/env bash
set -uo pipefail
AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
case "$AMD_TOOLS" in [A-Za-z]:/*)
  AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)";; esac
export PATH="${AMD_TOOLS}/Vivado/bin:$PATH"
cd "$(dirname "$0")"
mkdir -p ../../build/lab01 && cd ../../build/lab01
xvlog -sv ../../scripts/lab01_dfx/rtl/*.sv ../../scripts/lab01_dfx/tb/*.sv || exit 1
xelab -debug typical tb_dfx_behavior -s tb_dfx_sn -L work || exit 1
xsim tb_dfx_sn -runall > run.log 2>&1
grep -E "^PASS:|^FAIL:|\[TB" run.log | tail -8
grep -q "^PASS:" run.log && echo "PASS: lab01 behavioral sim" && exit 0
echo "FAIL: lab01 behavioral sim"; exit 1
