# Lab 07 -- AIE + NoC Simulation: Step-by-Step Solution

**Tool-conditional lab.** This workstation's unified Vitis 2025.2 install
does NOT ship `aiecompiler/aiesimulator` (verified); run on a workstation
with the full Vitis/AIE tools. Complete graph code:
`scripts/lab07_aie/graph/` (fir_kernels.h, fir_graph.h, test.cpp) +
`run_aieflow.sh` with the exact command sequence.

## Step-by-step

### Part 1-2: the FIR as an AIE graph
1. `fir_graph.h`: 4 AIE tiles, each an `fir_kernel` window kernel -- a
   polyphase decomposition (each tile filters one phase; outputs
   concatenate to the full response). `runtime<ratio>` 0.5.
2. Window discipline: `adf::window<512>` (256 x int16 in, int32 out),
   kernels are pure functions of their windows -- no global state, so
   x86sim and aiesim agree bit-for-bit.
3. `test.cpp`: impulse (4096) -> the concatenated outputs must reproduce
   the 32-tap coefficient set -- the SAME self-check Lab02 used, proving
   the methodology is engine-independent.

### Parts 3-4: simulation + reports
4. x86simulator: functional only (no cycles) -- catches graph errors.
5. aiecompiler + aiesimulator: cycle-approximate; open the graph view
   (tile count, ratio, DMA/lock usage) and record cycles per 256-block.

### Part 5: minimal NoC in Vivado
6. On a Versal part (VCK190 class): NoC + AIE IP, one SMC path DDR->AIE,
   `nocq/nocp` reports: read the latency/bandwidth of the path vs the
   AXI-on-US+ equivalent from Lab03.

### Part 6: same workload, two engines
7. Fill: Lab02 V3 (PL, measured 1166 cycles/1024-block) vs AIE (this lab,
   per-256-block x 4) -- same arithmetic, two acceleration models; write
   down when each wins (fine-grained SIMD streaming vs reconfigurable
   fabric datapaths).
