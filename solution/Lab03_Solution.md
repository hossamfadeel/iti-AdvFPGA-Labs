# Lab 3 Solution — AXI DMA: Streaming the FIR Accelerator
**Companion to Section 3: Advanced AXI: Custom IP, DMA, Streams**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Expected Console Output

A correct 1 MiB-buffer run prints this sequence over UART0 (CP2108 J83 ch0, 115200 8N1):

```
Lab 3: DMA streaming FIR
PASS: RX matches golden (group delay applied)
len=  4096 B  iters= 4096  time=234180 us  71 MiB/s
len= 65536 B  iters= 256  time= 52140 us  320 MiB/s
len=1048576 B  iters=   16  time= 30120 us  553 MiB/s
```

Times vary with board and tool revision; the trend is the graded artifact. PASS must
appear before any throughput line is trusted - throughput of wrong data is worthless.

## Representative Throughput

Numbers are representative of this design class (64-bit HP0, 200 MHz fabric, direct
register DMA, polling), not a specification. Repeat three runs per point and take the
median; the first iteration after programming is discarded as warm-up.

| Buffer | Iterations for 16 MiB | Throughput | Percent of 1600 MB/s ceiling |
| --- | --- | --- | --- |
| 4 KiB | 4096 | 65-75 MiB/s | ~4 percent |
| 64 KiB | 256 | 300-340 MiB/s | ~20 percent |
| 1 MiB | 16 | 530-580 MiB/s | ~35 percent |

## Common Failure Modes

- **Hang with S2MM never completing**: stream path broken between kernel and S2MM
  (unplugged stream, kernel never started, TLAST never asserted). MM2S completes; the
  S2MM engine waits forever for beats that never arrive. Read `MM2S_DMASR` (offset 0x34
  from the DMA base): MM2S idle, no error. S2MM halted bit clear (running), no error.
  A DMA hang with no error bits set is a stream stall until proven otherwise.
- **RX reads all zeros or stale chirp samples**: RX invalidate omitted. S2MM wrote correct
  data to DDR, but the CPU reads the pre-transfer cache lines. Symptom is data that
  matches a previous run's content or pure zeros. Fix: `Xil_DCacheInvalidateRange` after
  completion, before the CPU touches the buffer.
- **MM2S pushes garbage or old data**: TX flush omitted. CPU wrote the chirp into cache;
  MM2S read DDR lines that were never flushed. Symptom: golden-model mismatch from the
  first compared sample, or a pass only on the second run (the first run's writeback
  happens to have landed).
- **Pass on iteration 2+ only**: same root cause as above; the first iteration's cache
  writeback masked it. Always test from a cold start.
- **Mismatches at the first 5 compared samples only**: group delay not applied. Compare
  `rx_buf[i - GROUP_DELAY]` against `gold[i]`; the FIR pipeline fills over L-1 samples.
- **Verification passes but wrong length declared to S2MM**: the S2MM transfer completes
  only after it receives `bytes` worth of beats including TLAST at the right position. A
  length mismatch between MM2S and S2MM hangs the longer side.

## Question Answers

1. Flush pushes the CPU's dirty cache lines out to DDR so the MM2S engine reads fresh
   data: HP ports are non-coherent, so the DMA cannot snoop the A53's L1/L2. Invalidate
   marks the RX lines stale so the CPU re-fetches from DDR after S2MM writes. Omitting
   the flush yields MM2S reading old DDR contents (garbage input); omitting the
   invalidate yields the CPU reading stale cache contents (zeros or previous data).
2. 64 bits times 200 MHz gives 1600 MB/s per direction. Measured 553 MiB/s falls short
   due to: per-transfer CPU overhead (register writes, kernel start, polling handoff)
   serialized with each buffer; and DDR4 latency plus arbitration gaps that 16 in-flight
   iterations cannot fully hide at this buffer count. Cache flush/invalidate time also
   scales with buffer size and is included in the measurement.
3. The FIFOs provide elasticity and timing isolation. Even same-clock, the DMA issues
   long bursts while the HLS kernel consumes at a different instantaneous rate; without
   buffer depth the DMA stalls on TREADY mid-burst or the path closes timing on a long
   combinational TREADY chain (Section 3's skid-buffer rationale). Same clock removes
   the clock-domain-crossing need but not the rate-matching need.
4. Scatter-gather moves the per-buffer address/length/control writes into descriptors
   in DDR that the DMA fetches itself: the CPU submits a buffer by writing one descriptor
   pointer, and hardware chains onward. The cost is descriptor fetch traffic on the same
   HP port, which competes with payload beats unless coalescing thresholds are tuned.

---

**Presented by: Hossam Hassan, PhD**
