# Lab 02 -- HLS Optimization Deep Dive: Step-by-Step Solution

**Tested on this workstation (2025.2): ALL FOUR variants csim+csynth PASS.**

## How to run
cd scripts/lab02_hls
./run.sh            # v0..v3, each: csim (impulse + LCG-vs-golden) + csynth
python collect_dse.py   # measured table below

## Measured DSE table (this machine, 2025.2, 150 MHz target)

| Variant | II (max) | Block latency (cycles) | DSP48E2 | LUT | BRAM18 | %DSP of 2520 |
|---|---|---|---|---|---|---|
| V0 | 275589 | 275588 | 1 | 494 | 1 | 0.0% |
| V1 | 275589 | 275588 | 1 | 494 | 1 | 0.0% |
| V2 | 274565 | 274564 | 1 | 833 | 1 | 0.0% |
| V3 | **1166** | 1165 | 12 | 4883 | 0 | 0.5% |

## Reading the numbers (the whole point of the lab)

1. **V1 == V0 in block latency.** Pipelining TAP alone cannot fix a design
   whose time is dominated by the sequential SHIFT loop and the
   non-pipelined MAC loop. The pragma that targets the wrong bottleneck
   buys nothing -- check the Schedule Viewer, not your intuition.
2. **V2 (DATAFLOW) buys ~1000 cycles (~0.4%)**: compute dominates; the
   concurrent load/store processes overlap only the I/O wrappers.
3. **V3 is 236x faster** (II=1 per sample: latency ~ SAMPLES + TAPS):
   LOOP_SAMPLE pipelined + full UNROLL + ARRAY_PARTITION removes the
   recurrence and the memory port limit simultaneously.
4. **DSP count surprise (teachable)**: the lab predicted "DSP ~= tap
   count"; measured 12. Reason: int16x16 multipliers are small enough that
   Vivado implements most of the 128 MACs in LUT/fabric-carry logic and
   packs the rest -- resource tables report what the tool CHOSE, not what
   you imagined. Verify against the actual utilization report.

## Step-by-step build notes (what testing surfaced)

- 2025.2 flow: `vitis-run --tcl run_hls.tcl` replaces `vitis_hls -f`
  (variant selected via `FIR_SOL` env; per-variant projects `fir_proj_vN`
  so reports are not overwritten).
- `fir.h` needs the `fir_top` prototype for the TB, and the variant needs
  `-cflags "-I."` to find `fir.h` from `variants/`.
- The file-scope `#pragma HLS ARRAY_PARTITION variable=FIR_COEF` from the
  lab text is rejected by the 2025.2 csim parser ("only allowed in
  function scope") -- moved inside `compute()`; csynth semantics identical.
- Cosimulation: `FIR_COSIM=1 ./run.sh v3` (xsim-backed); v3's cosim latency
  should match csynth within a few percent.
- IP export happens automatically for v3 (`export_design -format ip_catalog`)
  -- the artifact Lab 3 consumes.

## Files
`fir.h` (types/coeffs/prototype), `fir_tb.cpp` (two-test TB),
`variants/fir_v0..v3.cpp`, `run_hls.tcl`, `run.sh`, `collect_dse.py`.
