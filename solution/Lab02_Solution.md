# Lab 2 Solution — Vitis HLS Deep Dive: FIR Optimization Study
**Companion to Section 2: Vitis HLS Deep Dive**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Reference Approach

One kernel, four solutions, one script. Interface pragmas fixed from V0
(axis in/out, s_axilite control); performance pragmas layered V1 PIPELINE,
V2 DATAFLOW restructure, V3 partition+unroll. 150 MHz target on
`xczu9eg-ffvb1156-2-e`. Export V3 as `fir_hls_ip`.

## Representative Tradeoff Table

Numbers below are representative of this design class at 150 MHz on
2023.2 - student values will differ in detail; the shape is what matters.

| Variant | Hot-loop II | Block latency (cycles) | DSP48E2 | LUT | BRAM_18K | % DSP |
| --- | --- | --- | --- | --- | --- | --- |
| V0 | n/a | ~524,000 | 3 | ~1,600 | 2 | 0.1% |
| V1 | 1 (TAP) | ~268,000 | 3 | ~1,900 | 2 | 0.1% |
| V2 | 1 (TAP) | ~266,000 | 3 | ~2,300 | 2 | 0.1% |
| V3 | 1 (SAMPLE) | ~1,300 | ~137 | ~5,500 | 0 | 5.4% |

Reading: V1 halves latency (TAP pipelined, SHIFT still serial). V2 adds
overlap worth a few percent - compute dominates, mirroring the deck's conv2d
table where DATAFLOW bought the last 10%. V3 collapses latency by ~400x:
one output per cycle at 150 MHz is ~150 Msamples/s against V0's ~0.29
Msamples/s, at the cost of ~137 DSPs (one per tap plus tree plumbing) -
about 5% of the device, 2% of its LUTs.

## Expected Viewer Observations

- V0 schedule: SHIFT and TAP as sequential blocks; acc chain visible.
- V1: TAP target II 1, achieved 1; block latency ~2x better, not 128x -
  the wall is the question this variant exists to pose.
- V2 dataflow graph: three processes overlapped, FIFO depths 2-4.
- V3: single pipelined loop, 128-wide parallel MAC body.

## Common Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| Achieved II = 2 in V1/V3 | clock too aggressive (e.g. 5 ns) | keep 6.667 ns, or accept and explain via recurrence |
| V3 II bound by memory | UNROLL without ARRAY_PARTITION | partition both x and FIR_COEF complete |
| csim Test 2 fails on second run | `static` history in kernel | local array initialized per call |
| First-rerun wipes solutions | open_project -reset every run | -reset on the first run only |
| FIR_COEF partition ignored | pragma far from declaration | place immediately after the include |

## Conceptual Question Answers

1. The serial SHIFT loop and the un-pipelined outer MAC loop. V3 folds the
shift into completely partitioned registers (a register-file shift is free in
the pipeline) and pipelines LOOP_SAMPLE at II=1 so successive samples overlap.
2. Achieved II sits at 128/2 = 64 class (BRAM two ports over 128 taps); the
BRAM row shows x/FIR_COEF still mapped to BRAM instead of registers -
Section 2's "memory-bound II" triage row.
3. Every process moves each token unconditionally (no conditional
read/write); a violation stalls the FIFO - cosim hangs or the dataflow
deadlock warning fires at csynth.
4. Yes: doubling needs ~2x128 DSPs (~274 of 2,520, ~11%). DSPs saturate
first; two samples per cycle via a wider UNROLL (two accumulator trees)
costs roughly double the DSP and LUT, still within the device.

## Grading Notes

Full credit requires: measured table with real report numbers (not copied),
achieved-II evidence, V3 cosim PASS, and a successful IP export that
instantiates in a scratch Vivado project.

---

**Presented by: Hossam Hassan, PhD**
