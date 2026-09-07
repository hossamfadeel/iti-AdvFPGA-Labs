# Lab 03 -- AXI DMA Streaming: Step-by-Step Solution

**Board lab.** Simulation of the stream mechanics is covered by Lab02's
cosim (the kernel contract) -- the value here is the complete,
compile-ready application and the scripted BD.

## Step-by-step

### Part 1: block design
Reproduce the lab table in `scripts/lab03_axi_dma/bd_lab03.tcl` spirit:
PS(S_AXI_HP0 64b, M_AXI_HPM0_FPD, FCLK0=200 MHz) -> AXI DMA (SG off,
32-bit stream) -> axis data FIFO (512) -> fir_hls_ip (Lab02 V3 export) ->
axis data FIFO -> S2MM. Golden rule kept: ONE clock, ONE reset.
After generation, check `xparameters.h` for `XPAR_AXIDMA_0_BASEADDR` and
`XPAR_FIR_0_BASEADDR` -- the app uses those symbols, never literals.

### Parts 3-4: the application (COMPLETE, no ellipses)
`scripts/lab03_axi_dma/sw/main.c` contains:
1. dma_init/kernel_init with the SG-disabled assertion,
2. chirp generator + float golden FIR (group delay (L-1)/2 = 5),
3. the verified transfer sequence: flush TX -> invalidate RX ->
   XFir_Start -> MM2S + S2MM -> poll -> invalidate -> compare,
4. the Part-4 harness `run_throughput()` for 4 KiB / 64 KiB / 1 MiB over
   a fixed 16 MiB with warm-up and `COUNTS_PER_SECOND` conversion.

### Expected results (record on the bench)
- PASS line on the chirp/golden check.
- MiB/s rising with buffer size; the 4 KiB point exposes per-iteration
  overhead (cache maintenance + register sequence + polling latency).
  Typical ZCU102 shape: hundreds of MiB/s at 4 KiB -> ~1.5-2 GiB/s at 1 MiB.

### Part 5 exercise (disconnect the return stream)
Predicted observations, in order: MM2S completes; S2MM stalls (no data);
`XAxiDma_Busy(DEVICE_TO_DMA)` never clears; kernel `ap_done` DOES set
(compute is done, only the return path is cut); ILA shows tvalid held high
into a FIFO nobody drains. The debugger's rule: read DMA state, do not
stare at streams -- the register view tells you which side is lying.
