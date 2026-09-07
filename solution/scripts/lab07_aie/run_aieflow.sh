#!/usr/bin/env bash
# Lab07: full AIE toolflow (REQUIRES a Vitis install with AIE tools; the
# unified 2025.2 install on this workstation does not ship aiecompiler).
# With Vitis classic / full unified:
#   aiecompiler -platform vck190.xpef graph/fir_graph.cpp
#   aiesimulator -x aiesim_output/options.txt
#   x86simulator  (functional)   then compare vs golden impulse response
echo "Lab07: run on a workstation with aiecompiler (see docs)"
echo "  1. aiecompiler  graph project  -> aiesim_output/"
echo "  2. x86simulator / aiesimulator -> compare impulse vs taps"
echo "  3. open aiesim_output/.../graph.aiecompile GDS: tile count, ratios"
echo "  4. compare cycles/256-block vs Lab02 V3 PL numbers"
