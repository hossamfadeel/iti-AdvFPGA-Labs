# Lab 04 -- Cache Coherency HP vs HPC: Step-by-Step Solution

**Board lab** (needs the Lab03 platform). Complete code:
`scripts/lab04_coherency/sw/lab4_parts.c` (parts 1-3 as callable stages,
using Lab03 helpers).

## Step-by-step

### Part 1: break it deterministically
1. Buffers 64 KiB, aligned 64: whole lines only, working set 128 KiB fits
   the 512 KiB L2 -- no self-eviction noise.
2. `prime_both_bugs()`: pre-dirty RX with 0xA5 (stale-read bug armed),
   keep TX dirty (device-stale-read bug armed).
3. Run with maintenance deleted: EXPECT many bad lines; RX[off]==0xA5
   proves the CPU read its own stale cache, not DDR (the S2MM data is
   fine -- you just never fetched it).

### Part 2: fix it, then price it
4. Restore flush-before-MM2S / invalidate-before-CPU-read: 0 bad lines
   over 100 runs.
5. `lab4_part2_timing()`: 4/16/64/256 KiB x 100 averages of
   flush+invalidate in us. Expect near-linear scaling with size
   (line-by-line clean/invalidate).

### Part 3: HPC0 behind the CCI
6. Vivado: untick S_AXI_HP0, tick S_AXI_HPC0 (64-bit, coherency enable);
   tie `s_axi_hpc0_fpd_axcache=4'hF`, `axdomain=2'h1`; rewire DMA to HPC0;
   regenerate; export XSA.
7. `lab4_part3()`: plain C, zero cache calls -> PASS 100/100.
   If not: attributes not tied (HP-style traffic never snoops) or DDR not
   mapped Normal Cacheable Inner-Shareable (`Xil_SetTlbAttributes`).

### Part 4-5: A/B and analysis
Record per size: HP raw window, HPC raw window, HP+maintenance total.
Expected shape: HPC raw slightly slower (snoop overhead), but total time
FLIPS in HPC's favor for small/frequent transfers; huge one-way streams
stay HP's win. The decision tree starts at "who touches the data, how
often" -- never at the port name.
