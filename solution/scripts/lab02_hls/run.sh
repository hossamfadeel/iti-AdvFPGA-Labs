#!/usr/bin/env bash
# Lab02 solution: run csim+csynth for a variant (or all four + DSE table)
set -uo pipefail
AMD_TOOLS="${AMD_TOOLS:-C:/AMDDesignTools/2025.2}"
case "$AMD_TOOLS" in [A-Za-z]:/*)
  AMD_TOOLS="/$(echo "$AMD_TOOLS" | cut -d: -f1 | tr 'A-Z' 'a-z')$(echo "$AMD_TOOLS" | cut -d: -f2)";; esac
RUN="$AMD_TOOLS/Vitis/bin/vitis-run.bat"
cd "$(dirname "$0")"
mkdir -p ../../build/lab02
if [ "${1:-all}" = "all" ]; then VARIANTS="v0 v1 v2 v3"; else VARIANTS="$1"; fi
FAILED=0
for v in $VARIANTS; do
  echo "== lab02 variant $v"
  FIR_SOL=$v timeout 1200 "$RUN" --tcl run_hls.tcl --work_dir . \
      > ../../build/lab02/hls_$v.log 2>&1
  log=../../build/lab02/hls_$v.log
  grep -q "^PASS: fir csim" "$log" || { echo "FAIL: $v csim"; tail -8 "$log"; FAILED=1; continue; }
  [ -f "fir_proj_$v/$v/syn/report/fir_top_csynth.rpt" ] ||     { echo "FAIL: $v csynth (no report)"; tail -8 "$log"; FAILED=1; continue; }
  echo "PASS: lab02 $v (csim + csynth)"
done
[ $FAILED -eq 0 ] && echo "PASS: lab02 HLS ($VARIANTS)" || echo "FAIL: lab02"
exit $FAILED
