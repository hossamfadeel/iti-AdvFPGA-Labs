#!/usr/bin/env bash
set -uo pipefail
AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
case "$AMD_TOOLS" in [A-Za-z]:/*)
  AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)";; esac
export PATH="${AMD_TOOLS}/Vivado/bin:$PATH"
cd "$(dirname "$0")"
mkdir -p ../../build/lab05 && cd ../../build/lab05
xvlog -sv ../../scripts/lab05_aurora/rtl/*.sv ../../scripts/lab05_aurora/tb/*.sv || exit 1
xelab -debug typical tb_aurora_loop -s tb_aur_sn -L work || exit 1
xsim tb_aur_sn -runall > run.log 2>&1
grep -E "^PASS:|^FAIL:|words " run.log | tail -4
grep -q "^PASS:" run.log && echo "PASS: lab05 BERT sim" && exit 0
echo "FAIL: lab05 BERT sim"; exit 1
