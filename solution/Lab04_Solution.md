# Lab 4 Solution — Cache Coherency: HP vs HPC on the Zynq MPSoC
**Companion to Section 4: Cache Coherency + Zynq UltraScale+ MPSoC**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Advanced

---

## Part 1 - Expected Failure Console (HP0, maintenance removed)

```
*** Lab 4 Part 1: HP0, cache maintenance REMOVED ***
tx=0x00201840 rx=0x002118C0 len=65536 aligned=64
run  1: mismatched lines     : 1024 / 1024
        first bad line       : 0 (rx offset 0x0000)
        lines holding 0xA5   : 1024
runs 2..10: identical
VERDICT: FAIL, deterministic
```

Every RX line serves the pre-dirtied 0xA5 pattern: S2MM landed fresh data in
DDR, but the CPU reads hit resident dirty lines (Section 4, bug two). TX is
also wrong: MM2S read DDR before the dirty sample lines were cleaned, so the
PL filtered yesterday's samples (Section 4, bug one). Both bugs are armed by
prime_both_bugs, which is why 1024 of 1024 lines mismatch every run.

## The Deterministic-Failure Recipe

Three ingredients, and removing any one lets luck back in:

1. Alignment: 64-byte aligned 64 KiB buffers make every operation whole-line,
   so no partial-line accident can mask or fake the effect.
2. Pre-dirty: memset RX to 0xA5 and fill TX immediately before the DMA, so
   every line in both buffers is resident and dirty when the DMA starts.
3. Geometry: a 128 KiB working set inside the 512 KiB shared L2 means nothing
   self-evicts during the experiment, so the dirty lines are still there to
   lie to the CPU (and, on TX, DDR is still old when the DMA reads it).

Shrink the buffer, skip the pre-dirty, or overflow the working set, and the
failure becomes statistical: heisenbug behavior returns.

## Part 2 - Restored Maintenance and Its Cost

```
*** Lab 4 Part 2: HP0 + flush/invalidate restored ***
run: PASS (0 / 1024 mismatched lines, 100 of 100 runs)
```

Maintenance cost measured with the A53 global timer, 100-call averages.
Representative numbers from a reference run, not guarantees; measure on your
own board and design:

| Buffer (KiB) | Flush (us) | Invalidate (us) | Total maint (us) | DMA window (us) | Maint / DMA |
|-------------:|-----------:|----------------:|-----------------:|----------------:|------------:|
| 4            | 1.4        | 1.6             | 3.0              | 27              | 11.1%       |
| 16           | 5.2        | 3.8             | 9.0              | 105             | 8.6%        |
| 64           | 19         | 15              | 34               | 420             | 8.1%        |
| 256          | 74         | 62              | 136              | 1670            | 8.1%        |

Reading: cost scales roughly linearly with bytes (one line operation per 64
bytes), flush costs more than invalidate because it moves data to DDR while
invalidate only discards, and maintenance settles near eight percent of the
DMA window for this geometry.

## Part 3 - HPC0 Configuration and Expected Console

Configuration recap: S_AXI_HP0_FPD unticked under AXI -> No Coherency;
S_AXI_HPC0_FPD ticked at 64-bit with coherency enable under AXI -> Coherency;
s_axi_hpc0_fpd_axcache tied to 4'hF and s_axi_hpc0_fpd_axdomain to 2'h1 (Inner
Shareable); DMA rewired to HPC0, bitstream regenerated, XSA exported.

```
*** Lab 4 Part 3: S_AXI_HPC0 via CCI, zero cache calls ***
runs 1..100: PASS (0 / 1024 mismatched lines)
Xil_DCache* calls in the data path: 0
```

If HPC still fails: first confirm the attribute constants are actually driven
(deck gotcha: an HPC port with plain HP-style attributes works but never
snoops), then confirm DDR is mapped Normal cacheable Inner Shareable by the
BSP translation tables (Xil_SetTtbAttributes class of fix).

## Part 4 - A/B Results (representative)

| Buffer (KiB) | HP raw (us) | HPC raw (us) | Raw delta | HP maint (us) | HP total (us) | HPC total (us) | Total winner |
|-------------:|------------:|-------------:|----------:|--------------:|--------------:|---------------:|-------------|
| 4            | 27          | 29           | 7.4%      | 3.0           | 30.0          | 29             | HPC         |
| 16           | 105         | 112          | 6.7%      | 9.0           | 114           | 112            | HPC         |
| 64           | 420         | 447          | 6.4%      | 34            | 454           | 447            | HPC         |
| 256          | 1670        | 1780         | 6.6%      | 136           | 1806          | 1780           | HPC (thin)  |

Two conclusions. Raw bandwidth: HP is ahead roughly 6 to 7 percent at every
size, confirming that snoop traffic through the CCI is not free (deck case
study: 5 to 10 percent class at 64 KiB). Total time: HPC wins at all measured
sizes because per-byte maintenance (~8 percent of the window here) exceeds the
snoop premium (~6 percent). HP wins overall only when maintenance is zero
(CPU never touches a one-way stream) or amortized (buffer touched once, moved
many times); then the raw-bandwidth premium is the whole story.

## Conceptual Question Answers

1. Luck mechanisms: (a) eviction luck: a small buffer's dirty lines get
   evicted (writing back to DDR) before the DMA looks, so DDR happens to be
   current; smaller buffers fit in fewer sets and evict more often with any
   other memory traffic. (b) Cold cache: if the RX lines were never fetched,
   the CPU read misses and refetches fresh DDR; alignment near a 64-byte
   boundary changes how many lines the buffer occupies. (c) Coincidence: DDR
   already held the same bytes (fresh .bss zeros matching a zero golden
   region), which alignment and data choice decide. Optimization level and
   printf shift all three by perturbing cache footprint: the heisenbug tell.

2. Flushing RX after the S2MM completes orders the dirty CPU lines to be
   written back over the DMA's fresh DDR data, corrupting the one truth that
   existed. Invalidate-before-DMA is correct for a device-written buffer:
   stale lines are dropped first, the DMA then writes DDR unopposed, and the
   next CPU read misses and fetches the fresh bytes. The deck's eviction trap
   is exactly this writeback-overwrite in accidental form.

3. HP ports join the FPD interconnect below the CCI, so their traffic reaches
   DDR without ever consulting the APU's caches: keeping the two truths
   consistent is software's job (rung 2, the contract is on you). HPC ports
   terminate on the CCI, whose snoop filter holds the APU L2 accountable for
   dirty lines: with AxCACHE 1111 and Inner Shareable domain, DMA reads hit
   up-to-date data and DMA writes invalidate or update resident lines. On
   HPC the interconnect owns the problem (rung 3).

4. Video pipeline: HP port. The CPU never reads the payload, so no invalidate
   is ever due, and the one-time descriptor write costs one tiny flush; Part 2
   shows maintenance scales with bytes, so keeping it off the payload is the
   whole win, and Part 4 shows HP's raw premium. Doorbell ring: HPC port.
   Part 2's per-call floor dominates a 1 KiB ring moved constantly, and zero
   maintenance removes an ordering bug class from the doorbell path. Linux
   echo: dma-coherent device tree property with dma_alloc_coherent for the
   ring (rung 3), streaming dma_map_single or dmabuf/CMA heaps for the frames
   (rung 2 maintenance, amortized over the buffer lifetime).

---

**Presented by: Hossam Hassan, PhD**
