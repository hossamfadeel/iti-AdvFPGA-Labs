# Lab 4 — Cache Coherency: HP vs HPC on the Zynq MPSoC
**Companion to Section 4: Cache Coherency + Zynq UltraScale+ MPSoC**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Advanced

---

## Introduction

Section 4 climbed the solutions ladder: rung 1 uncached memory, rung 2 explicit
cache maintenance (clean TX before the device reads it, invalidate RX before
the device writes it), rung 3 hardware coherency through the CCI. This lab
produces the evidence on silicon, reusing the Lab 3 datapath unchanged (AXI
DMA feeding fir_hls_ip, the kernel from Lab 2). Arc in one line: Lab 2 built
the kernel, Lab 3 moved data fast, Lab 4 moves it correctly.

## Objectives

- Reproduce both Section 4 failure modes on demand and explain lucky passes.
- Measure the flush plus invalidate cost versus buffer size on the A53
  global timer.
- Move the datapath to coherent S_AXI_HPC0; prove correctness with zero
  cache calls.
- Quantify the bandwidth price of coherency; pick ports by traffic shape.

## Prerequisites

- ZCU102 (part xczu9eg-ffvb1156-2-e): DDR4 SODIMM in J1 (64-bit DDR4-2666),
  JTAG on J2, UART on J83 channel 0 at 115200 8N1, Vivado / Vitis 2023.2.
- Your Lab 3 project: block design plus bare-metal A53 application driving
  the DMA + fir_hls_ip loop.
- Fixed facts: 4x S_AXI_HP ports non-coherent; 2x S_AXI_HPC ports coherent
  through the CCI; the SMMU is optional and bypassed in this bare-metal lab.
  A53 cluster: per-core L1 plus a 512 KiB shared L2, 64-byte lines.

## Part 1 - Break It: HP0 with the Cache Maintenance Deleted

### 1.1 Confirm the baseline

Program the FPGA over JTAG (J2), open the serial terminal on J83 channel 0
(115200 8N1), and run Lab 3 unmodified. It passes: every DMA is bracketed
by a TX flush and an RX invalidate. That is rung 2; the contract is on you.

### 1.2 Engineer a deterministic failure

Naively deleting the calls does break things, but small buffers fail
statistically: lines evict by luck, cold caches have nothing stale to serve,
and the bug moves with printf or optimization level (a heisenbug).
Engineer the geometry instead:

- 64 KiB buffers aligned to 64 bytes: whole lines only, no partial-line
  accidents masking the effect.
- 128 KiB working set: fits inside the 512 KiB shared L2, so nothing
  self-evicts during the experiment window.
- Pre-dirty RX with a known pattern right before the DMA and keep TX dirty
  with fresh samples: both Section 4 bugs armed on every run.

### 1.3 Failure harness

Delete the two maintenance calls (kept as comments) and add a verification
loop that reports the first mismatching cache line; fill_fir_input,
dma_fir_once, and golden_fir_output are your Lab 3 helpers.

```c
/* lab4_part1.c - HP0 path, cache maintenance REMOVED (broken on purpose) */
#define BUF_BYTES  (64 * 1024)          /* fits in the 512 KiB shared L2 */
#define STALE_BYTE 0xA5
#define LINE       64                   /* the atom of caching           */
static u8 tx[BUF_BYTES] __attribute__ ((aligned (LINE)));
static u8 rx[BUF_BYTES] __attribute__ ((aligned (LINE)));

static void prime_both_bugs(void)       /* arms both Section 4 bugs      */
{
    memset(rx, STALE_BYTE, BUF_BYTES);  /* RX lines resident and dirty   */
    fill_fir_input(tx, BUF_BYTES);      /* TX dirty, DDR still old       */
    /* Lab 3 had, now DELETED:
     *   Xil_DCacheFlushRange((UINTPTR)tx, BUF_BYTES);
     *   Xil_DCacheInvalidateRange((UINTPTR)rx, BUF_BYTES);             */
}

static int verify_rx(u32 len, u32 *first_bad, u32 *stale_lines)
{
    const u8 *gold = golden_fir_output();  /* your Lab 3 golden model   */
    u32 n = 0, off;
    *stale_lines = 0;
    for (off = 0; off < len; off += LINE)
        if (memcmp(rx + off, gold + off, LINE) != 0) {
            if (n == 0) *first_bad = off;  /* first mismatching line    */
            if (rx[off] == STALE_BYTE) (*stale_lines)++;
            n++;
        }
    return n;
}

void lab4_part1(void)
{
    u32 first = 0, stale = 0;
    prime_both_bugs();
    dma_fir_once(tx, rx, BUF_BYTES);     /* MM2S -> fir_hls_ip -> S2MM   */
    xil_printf("bad lines %d/%d, first at line %d, stale %d\r\n",
               verify_rx(BUF_BYTES, &first, &stale),
               BUF_BYTES / LINE, first / LINE, stale);
}
```

## Part 2 - Fix One: Restore Maintenance on HP0 and Price It

Un-delete the two calls with the Section 4 ordering: flush TX before MM2S,
invalidate RX before S2MM, never touch either buffer while the DMA owns it.
Confirm 0 mismatched lines over 100 runs. Then time both calls with the A53
global timer; XTime is the Vitis API, and COUNTS_PER_SECOND from the BSP
converts counts to microseconds:

```c
static u32 time_maintenance(u8 *t, u8 *r, u32 len)  /* result in us */
{
    XTime t0, t1;
    XTime_GetTime(&t0);
    Xil_DCacheFlushRange((UINTPTR)t, len);      /* clean TX: dirty -> DDR */
    Xil_DCacheInvalidateRange((UINTPTR)r, len); /* drop RX: stale gone    */
    XTime_GetTime(&t1);
    return (u32)((t1 - t0) * 1000000ULL / COUNTS_PER_SECOND);
}
```

For each size in {4, 16, 64, 256} KiB, average 100 calls and record: flush
alone, invalidate alone, total maintenance, the DMA window, and the
maintenance-to-DMA ratio, with the FIR configured exactly as in Lab 3.

## Part 3 - Fix Two: Move the Datapath to Coherent S_AXI_HPC0

### 3.1 PS reconfiguration in Vivado

Double-click the Zynq UltraScale+ MPSoC block to open the PS-UltraScale+
Configuration page:

1. PS-PL Configuration -> AXI -> No Coherency: untick S_AXI_HP0_FPD.
2. PS-PL Configuration -> AXI -> Coherency: tick S_AXI_HPC0_FPD, set data
   width to 64, tick the coherency enable. The PL now holds a seat at the
   CCI, the snoop-filtered interconnect the APU joins ACE-style.
3. With coherency enabled the PS exposes the HPC0 attribute inputs: tie
   s_axi_hpc0_fpd_axcache[3:0] to 4'hF (cacheable, read and write
   allocate) and s_axi_hpc0_fpd_axdomain[1:0] to 2'h1 (Inner Shareable),
   per the Section 4 table on making HPC traffic snoopable.
4. Rewire the DMA path from HP0 to HPC0 (Connection Automation), validate,
   regenerate the bitstream, export the updated XSA to Vitis.

### 3.2 The payoff shot: plain C

The loop keeps nothing but ordinary cached buffers; no cache calls:

```c
/* lab4_part3.c - S_AXI_HPC0 behind the CCI: correct by construction */
void lab4_part3(void)
{
    fill_fir_input(tx, BUF_BYTES);         /* plain cached writes    */
    dma_fir_once(tx, rx, BUF_BYTES);       /* snooped end to end     */
    int rc = memcmp(rx, golden_fir_output(), BUF_BYTES);
    xil_printf("HPC0, zero cache calls: %s\r\n", rc ? "FAIL" : "PASS");
}
```

### 3.3 Run and troubleshoot

Expect PASS 100/100. If HPC still shows stale data, walk the Section 4
gotcha list: attribute constants not driven (an HPC port with plain
HP-style attributes never snoops), then DDR not mapped Normal cacheable
Inner Shareable by the BSP tables (Xil_SetTlbAttributes).

## Part 4 - A/B: HP with Maintenance vs HPC with None

Same buffers, FIR, and 100-iteration averages. Per size record: HP raw DMA
window, HPC raw DMA window, raw delta percent, HP maintenance from Part 2,
HP total, HPC total, and the total-time winner (throughput counts 2 x len
bytes per iteration). Does coherency cost bandwidth, and by how much? Does
removed maintenance flip the winner, and at which sizes?

## Part 5 - Analysis: When HPC Wins, When HP Wins

- HPC wins when buffers are small and transfers frequent: maintenance is a
  per-call cost that dominates small moves; chatty shared rings get
  correctness with zero calls and no contract to audit.
- HP wins for huge one-way streams the CPU never reads (no maintenance due)
  or buffers touched once but moved many times (one flush amortized over N
  moves), where the raw-bandwidth premium is the whole story.
- Cross-check against the Section 4 decision tree: start from who touches
  the data and how often, not from the port name. Under Linux the same
  choice is allocation policy: dma-coherent declarations and
  dma_alloc_coherent map to rung 3 hardware; streaming dma_map_single and
  dmabuf/CMA heaps map to rung 2.

## Verification Checkpoints

| # | Checkpoint | Expectation |
|---|------------|-------------|
| 1 | Part 1 harness, 10 consecutive runs | FAIL every run, first bad line 0, 1024/1024 lines |
| 2 | Part 2 restored maintenance, 100 runs | PASS every run, sweep recorded for 4 sizes |
| 3 | Part 3 HPC build, 100 runs | PASS, zero Xil_DCache calls in the loop |
| 4 | Part 4 A/B table recorded | raw delta percent plus totals per size |

**Quantitative targets:**
- Part 1: deterministic failure, 10 of 10 runs, all 1024 lines mismatched,
  stale-pattern count above 1000 lines (no luck variance).
- Part 2: maintenance grows roughly linearly with bytes; at 64 KiB expect
  flush plus invalidate in the tens of microseconds, a single-digit
  percentage of the DMA window (representative values in the solution).
- Part 3: PASS 100 of 100 runs with the loop free of cache calls.
- Part 4: raw HPC bandwidth a few percent below HP (deck case study: the
  5 to 10 percent class at 64 KiB); totals flip toward HPC at small sizes.

## Conceptual Questions

1. A colleague runs your Part 1 harness with 256-byte buffers and it passes
   200 runs straight. Give three distinct mechanisms that let an
   unmaintained HP transfer succeed, and how size and alignment affect each.
2. You "fix" the RX side by calling Xil_DCacheFlushRange on rx after the
   S2MM completes instead of invalidating before it starts. Explain how
   that destroys data, and why invalidate-before-DMA is correct for a
   device-written buffer.
3. HP0 and HPC0 both end at the same DDR controller. In terms of where each
   port joins the interconnect relative to the CCI, explain why identical
   software is correct on HPC0 and broken on HP0, and who owns the problem
   in each case.
4. Your product has a 4K video pipeline (CPU writes descriptors once,
   never touches payload) plus a 1 KiB doorbell ring the CPU and PL update
   constantly. Assign ports using your Part 2 and Part 4 numbers, then name
   the Linux-side mechanisms expressing the same assignment.

---

**Presented by: Hossam Hassan, PhD**
