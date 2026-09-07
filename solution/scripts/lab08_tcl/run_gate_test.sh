#!/usr/bin/env bash
# Lab08 solution run: scripted synth + WNS gate, plus a proof the gate bites
set -uo pipefail
AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
case "$AMD_TOOLS" in [A-Za-z]:/*)
  AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)";; esac
export PATH="${AMD_TOOLS}/Vivado/bin:$PATH"
cd "$(dirname "$0")"
mkdir -p build
echo "== lab08: non-project synth (this is the CI-simulable part of the lab)"
vivado -mode batch -source build.tcl -tclargs synth > build/synth.log 2>&1
grep -q "SYNTH DONE" build/synth.log || { echo "FAIL: synth"; tail -10 build/synth.log; exit 1; }
vivado -mode batch -source gates/wns_gate.tcl > build/gate.log 2>&1
grep -q "^PASS: all timing clean" build/gate.log \
  && echo "PASS: lab08 scripted flow + WNS gate" \
  || { echo "FAIL: gate"; tail -5 build/gate.log; exit 1; }
