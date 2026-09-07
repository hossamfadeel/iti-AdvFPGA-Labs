#!/usr/bin/env bash
# Master runner for all lab solutions. Reports what is TESTED here vs
# board/tool-conditional.
S="$(cd "$(dirname "$0")" && pwd)"
pass=0; fail=0; board=""
run() {  # run <name> <script>
  echo "===== $1 ====="
  if "$2" > /tmp/lab_$1.log 2>&1; then
    tail -1 /tmp/lab_$1.log; echo "RESULT $1: PASS"; pass=$((pass+1))
  else
    tail -5 /tmp/lab_$1.log; echo "RESULT $1: FAIL"; fail=$((fail+1))
  fi
}
run lab01 "$S/scripts/lab01_dfx/run_sim.sh"
run lab02 "$S/scripts/lab02_hls/run.sh"
run lab05 "$S/scripts/lab05_aurora/run_sim.sh"
run lab08 "$S/scripts/lab08_tcl/run_gate_test.sh"
echo "----- board / tool-conditional (complete artifacts, run at the bench) -----"
echo "lab03: scripts/lab03_axi_dma (BD + complete bare-metal app)"
echo "lab04: scripts/lab04_coherency (parts 1-3 staged code)"
echo "lab06: scripts/lab06_dpu     (VART app + docker/board scripts)"
echo "lab07: scripts/lab07_aie     (graph code + flow; needs aiecompiler)"
echo "--------------------------------------------------------------------------"
echo "TESTED HERE: $pass PASS, $fail FAIL"
[ $fail -eq 0 ]
