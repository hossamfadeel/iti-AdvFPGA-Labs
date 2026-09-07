# Lab 3 — AXI DMA: Streaming the FIR Accelerator
**Companion to Section 3: Advanced AXI: Custom IP, DMA, Streams**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Introduction

Section 3 turned AXI from scenery into engineering: you saw the handshake channels,
outstanding transactions, and the two DMA engines that bridge memory-mapped DDR and the
AXI4-Stream world. This lab builds the complete streaming accelerator path that the deck's
case study promised:

```
DDR4 -> AXI DMA (MM2S) -> [axis data FIFO] -> fir_hls_ip -> [axis data FIFO] -> (S2MM) -> DDR4
```

The Cortex-A53 in the PS never touches a data sample. It programs the DMA in direct
register mode (no scatter-gather, no descriptor bypass), starts the HLS FIR kernel from
Lab 2, and polls for completion. Everything between is TVALID/TREADY and TLAST.

One detail will bother you, and it should: the explicit cache maintenance calls around
every transfer. HP ports are non-coherent. That is not an accident - it is the setup for
Lab 4, where the same design moves from S_AXI_HP0 to S_AXI_HPC0 and the cache calls
disappear.

## Objectives

- Assemble the PS-initiated streaming datapath: Zynq PS, AXI DMA, axis data FIFOs for
  elasticity, and the Lab 2 `fir_hls_ip`, all on one 200 MHz fabric clock.
- Configure S_AXI_HP0 as 64-bit and control the DMA and kernel through PS HPM0.
- Take the design through bitstream generation with correct PL clock/reset assignment.
- Write a bare-metal A53 harness that moves a chirp through the FIR, verifies it
  bit-exactly against a golden C model (accounting for FIR group delay), and measures
  sustained throughput with the A53 global timer.
- Observe, and then explain, why small buffers crush throughput.

## Prerequisites

- Lab 2 completed: `fir_hls_ip` exported from Vitis HLS (`Export > Export RTL` or
  `vitis-run --export`), packaged and added to your Vivado IP repository.
- No Lab 2 IP? Regenerate a fallback in about 10 minutes: an HLS kernel with one
  `hls::stream<data_t>` input port, one output port, and a loop doing
  `out.write(in.read() * GAIN);` with a gain of 2. Interface: `axis` on both ports,
  `s_axilite` control, `ap_ctrl_hs`. Same block design, same harness (golden model is a
  multiply instead of a convolution), same measurements.
- Tools: Vivado and Vitis 2023.2. Serial terminal at 115200 8N1 on CP2108 J83 channel 0
  (UART0, MIO18/19).
- Familiarity: XAxiDma bare-metal flow from the Section 3 code slide (`XAxiDma_LookupConfig`,
  `XAxiDma_CfgInitialize`, `XAxiDma_Reset`, `XAxiDma_SimpleTransfer`).

## Part 1: Block Design

Create a Vivado project targeting part `xczu9eg-ffvb1156-2-e`, board part
`xilinx.com:zcu102:part0:3.3`. Create a block design and add the following connections.

Clock choice: drive the PL fabric from PS FCLK0 at 200 MHz. The USER_SI570 programmable
clock could give you 300 MHz, but it adds a board automation step, changes nothing about
the DMA mechanics under study, and 200 MHz already far exceeds what this datapath needs.
One clock, one reset domain, fewer mysteries. Revisit SI570 when a lab actually needs the
headroom.

| Connection | From | To | Notes |
| --- | --- | --- | --- |
| DMA control | PS M_AXI_HPM0_FPD | AXI DMA S_AXI_LITE | via AXI interconnect, 1 master |
| Kernel control | PS M_AXI_HPM0_FPD | fir_hls_ip s_axi_control | same interconnect, 2nd master port |
| Stream out | AXI DMA M_AXIS_MM2S | axis data FIFO S_AXIS | depth 512, asynchronous not needed (same clock) |
| Stream compute | axis data FIFO M_AXIS | fir_hls_ip in_stream | width matches kernel port |
| Stream return | fir_hls_ip out_stream | second axis data FIFO S_AXIS | elasticity before S2MM |
| Stream in | second FIFO M_AXIS | AXI DMA S_AXIS_S2MM | |
| Read data | AXI DMA M_AXI_MM2S | PS S_AXI_HP0_FPD | 64-bit HP0 |
| Write data | AXI DMA M_AXI_S2MM | PS S_AXI_HP0_FPD | shared port, read+write |
| Clock | PS pl_clk0 (200 MHz) | all PL clocks | DMA, FIFOs, kernel, interconnect |
| Reset | PS pl_resetn | all PL resets | active low |

PS configuration, in the reconfigure dialog:

1. Add FPD slave port `S_AXI_HP0_FPD`. In its tab, set HP0 data width to 64 bits.
2. Enable `M_AXI_HPM0_FPD` for control (64-bit default is fine).
3. PS DDR4 is fixed by the board preset: single SODIMM on J1, 64-bit, DDR4-2666. Confirm
   the board preset filled it in; do not hand-edit timings.
4. FCLK0 = 200 MHz; `pl_clk0` drives the fabric; `pl_resetn` for the PL.

AXI DMA IP settings: disable Scatter Gather Engine entirely (direct register mode only).
Enable Micro DMA? No - leave it off; classic mode with one stream width. Set the stream
data width to match your FIR sample port (typically 32 bits: one `data_t` per beat).
Leave the buffer length register defaults alone; our buffers are far below limits.

axis data FIFOs: purpose is elasticity and clock-domain safety margin. Even with one
clock, the FIFOs absorb burst arrival versus kernel consumption-rate mismatch, and their
skid-buffer register slices break the TREADY combinational chain that Section 2 of the
deck warned about. Depth 512 is generous; depth 16 would also work.

Run Connection Automation only for the 200 MHz clock and reset nets after manual wiring
of the stream path. Validate the design (F6). Expected warnings: none fatal; interconnect
width conversion is handled automatically where the 64-bit HP side meets narrower
internal streams.

## Part 2: Synthesis, Implementation, Bitstream

Generate the bitstream. Then:

1. `File > Export > Export Hardware` - include bitstream, produce XSA.
2. In Vitis, create a platform from the XSA.

Under the hood, confirm PL clock assignment: pl_clk0 at 200 MHz appears in the PSU
configuration and the CFD, and pl_resetn is routed. If you named the FCLK differently or
touched dividers, the PSU address map still lists the FPD slaves at the addresses the
xparameters header will reflect - check `xparameters.h` after platform generation for
`XPAR_AXIDMA_0_BASEADDR` and the kernel base; you will need both numbers.

Flash the bitstream and boot. Console comes up on UART0 at 115200 8N1 over the J83 CP2108
channel 0 cable. JTAG (J2) remains available for ILA later.

## Part 3: Bare-Metal A53 Application

Create an A53 bare-metal application on the exported platform. The harness below is
complete except where marked; ellipses denote repetitive sections, not logic.

Data shape: FIR length L = 11 (Lab 2 default; adjust if yours differs), sample type
`data_t` = `float`. N = 16384 samples. Group delay = (L-1)/2 = 5 samples: RX[0..4]
compared against golden[5..9] onward. The final 5 golden outputs have no RX counterpart.

```c
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include "xfir.h"            /* generated by HLS export, name matches IP */

#define N_SAMPLES 16384
#define FIR_TAPS  11
#define GROUP_DELAY ((FIR_TAPS - 1) / 2)

static float tx_buf[N_SAMPLES] __attribute__ ((aligned (32)));
static float rx_buf[N_SAMPLES] __attribute__ ((aligned (32)));
static float gold[N_SAMPLES];

static XAxiDma dma;

static int dma_init(UINTPTR base)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfigBase(base);
    if (!cfg) return -1;
    if (XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) return -1;
    if (XAxiDma_HasSg(&dma)) { xil_printf("SG enabled - config error\r\n"); return -1; }
    XAxiDma_Reset(&dma);
    while (!XAxiDma_ResetIsDone(&dma)) ;
    return 0;
}

static int kernel_init(XFir *fir, UINTPTR base)
{
    XFir_Config *cfg = XFir_LookupConfigBase(base);
    if (!cfg) return -1;
    return XFir_CfgInitialize(fir, cfg);
}

static void gen_chirp(float *x, int n)
{
    for (int i = 0; i < n; i++)
        x[i] = 1000.0f * sinf(2.0f * 3.14159265f * (0.002f * i) * i / 200.0f);
}

static void golden_fir(const float *x, float *y, int n)
{
    static const float taps[FIR_TAPS] = { /* copy Lab 2 coefficients */ 0.0f };
    for (int i = 0; i < n; i++) {
        float acc = 0.0f;
        for (int k = 0; k < FIR_TAPS && k <= i; k++) acc += taps[k] * x[i - k];
        y[i] = acc;
    }
}

static int verify(void)
{
    for (int i = GROUP_DELAY; i < N_SAMPLES; i++)
        if (fabsf(rx_buf[i - GROUP_DELAY] - gold[i]) > 1e-3f) {
            xil_printf("MISMATCH at %d: %d vs %d\r\n", i,
                       (int)(rx_buf[i - GROUP_DELAY] * 1000), (int)(gold[i] * 1000));
            return -1;
        }
    return 0;
}

int main(void)
{
    XFir fir;
    XTime t0, t1;

    xil_printf("\r\nLab 3: DMA streaming FIR\r\n");

    if (dma_init(XPAR_AXIDMA_0_BASEADDR)) return 1;
    if (kernel_init(&fir, XPAR_FIR_0_BASEADDR)) return 1;

    gen_chirp(tx_buf, N_SAMPLES);
    golden_fir(tx_buf, gold, N_SAMPLES);

    const UINTPTR bytes = N_SAMPLES * sizeof(float);

    /* Cache maintenance: HP0 is non-coherent. Flush dirty TX lines to DDR so
       MM2S reads fresh data; invalidate RX lines so the CPU re-fetches what
       S2MM wrote. Omit either and you will read stale cache content. */
    Xil_DCacheFlushRange((UINTPTR)tx_buf, bytes);
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);

    XFir_Start(&fir);

    XAxiDma_SimpleTransfer(&dma, (UINTPTR)tx_buf, bytes, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)rx_buf, bytes, XAXIDMA_DEVICE_TO_DMA);

    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE)) ;
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA)) ;

    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);

    if (verify() == 0) xil_printf("PASS: RX matches golden (group delay applied)\r\n");
    else               xil_printf("FAIL\r\n");

    return 0;
}
```

Timing note: `XTime_SetTime(0)` is called once in the BSP; `XTime_GetTime` returns
ticks at the BSP-configured global-timer frequency (check `COUNTS_PER_SECOND` in
`xtime_l.h`). Convert with `t / COUNTS_PER_SECOND`.

Buffer alignment to 32 bytes keeps flush/invalidate from touching neighbor cache lines
belonging to other variables - a classic silent-corruption source.

## Part 4: Throughput Harness

Wrap the transfer sequence in a loop that moves a fixed total of 16 MiB per configuration,
timed with the global timer:

```c
#define TOTAL_BYTES (16u * 1024 * 1024)

static void run_throughput(int samples_per_iter)
{
    const UINTPTR bytes = samples_per_iter * sizeof(float);
    const int iters = TOTAL_BYTES / bytes;
    XTime t0, t1;

    /* warm-up one pass so TLB and DMA paths are primed */
    one_transfer(bytes);

    XTime_GetTime(&t0);
    for (int i = 0; i < iters; i++)
        one_transfer(bytes);       /* flush, start, both directions, poll, invalidate */
    XTime_GetTime(&t1);

    u64 dt_us = ((t1 - t0) * 1000000ULL) / COUNTS_PER_SECOND;
    u32 mbps  = (u32)((TOTAL_BYTES * 1ULL) / dt_us);   /* MiB per second */
    xil_printf("len=%6d B  iters=%5d  time=%lu us  %lu MiB/s\r\n",
               bytes, iters, dt_us, mbps);
}
```

Repeat for 4 KiB, 64 KiB, and 1 MiB buffers (1024, 256, and 16 iterations respectively,
all covering the same 16 MiB). Record the three numbers. Then explain the trend you see
before reading the solution notes: what per-iteration cost does a small buffer amortize
over fewer bytes? Include in your written answer: cache maintenance cost, register write
sequence, kernel start, and MM2S/S2MM completion polling latency as candidates.

## Part 5: Exercises - Reading DMA State Without a Stream

This exercise builds the debugging instinct Section 3's bug gallery is about.

1. In the block design, disconnect the wire from `fir_hls_ip` `out_stream` to the S2MM-side
   FIFO (or delete the FIFO feeding `S_AXIS_S2MM`). Regenerate the bitstream.
2. Run a single transfer. The harness will hang in `while (XAxiDma_Busy(...DEVICE_TO_DMA))`.
3. Attach the debugger (or add a register dump) and read `MM2S_DMASR` and `S2MM_DMASR`
   at the DMA base from `xparameters.h`: offset 0x34 for MM2S status, 0x34 for S2MM
   (see the AXI DMA product guide for the register map; the driver constants in
   `xaxidma_hw.h` give bit positions: `XAXIDMA_HALTED_MASK`, `XAXIDMA_IDLE_MASK`,
   `XAXIDMA_ERR_*` masks).
4. Expected: MM2S reports idle with no error - it pushed every beat and the FIFO accepted
   them; the hang is S2MM waiting for beats that never arrive. Note which bit proves the
   engine is halted-versus-running and which bits, if any, indicate an error versus a mere
   wait. Restore the connection afterward.

## Verification Checkpoints

**Quantitative targets:**

- RX buffer bit-exact against golden C model after accounting for the 5-sample group
  delay, tolerance 1e-3 for float accumulation order.
- No `XAXIDMA_ERR_*` bits set in either DMASR after any run.
- Sustained throughput for 1 MiB buffers greater than 500 MiB/s. Record your measured
  numbers; the solution lists a representative range for this design class.
- Buffer sweep shows monotonic throughput degradation toward 4 KiB, and your written
  explanation identifies at least three per-transfer overhead sources.
- Exercise: correctly identify which DMA engine reports the fault state on an unplugged
  stream and why the other one reports success.

## Conceptual Questions (4)

1. Why must the TX buffer be flushed and the RX buffer invalidated, when both operations
   are called "cache maintenance"? What stale result does each omission produce?
2. The deck's throughput slide computes peak as bytes-per-beat times clock. With HP0 at
   64 bits and 200 MHz, what is the theoretical ceiling, and why does your measured 1 MiB
   number fall short of it? Name two specific loss mechanisms.
3. Why does the design need axis data FIFOs at all if producer and consumer run on the
   same 200 MHz clock? What failure mode appears without them?
4. In direct register mode the CPU issues one register-write sequence per buffer. What
   does scatter-gather mode change about CPU involvement, and what new traffic does it
   introduce? (Deck slide: "Direct register vs scatter-gather.")

---

**Presented by: Hossam Hassan, PhD**
