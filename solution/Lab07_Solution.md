# Lab 7 Solution — Versal AIE + NoC: Toolflow Without Hardware
**Companion to Section 7: Versal ACAP: NoC & AI Engines**
**Board:** None (Versal ACAP toolflow simulation; NOT possible on ZCU102) | **Level:** Advanced

---

## Reference Approach

Three-kernel FIR graph (fir16_low, fir16_high, vec_add16) on window<256>
int16 channels; x86sim bit-exact against a golden model that replicates the
per-half Q15 truncation; aiesim for cycle-approximate behavior; compiler
reports for mapping and stalls. NoC: CIPS -> NMU -> NSU -> MC0 path, two QoS
scenarios, report_noc_qos comparison.

## Expected Simulation Output (representative)

```
$ x86simulator --pkg-dir=Work
INFO: Simulator running ......
INFO: Simulator exit.
$ diff output.txt golden.txt && echo BIT-EXACT
BIT-EXACT
```

A mismatch confined to +/- 1 LSB usually means the golden model does not
replicate the per-half truncation - fix golden.py, not the kernels.

## Representative Kernel Metrics (from trace; yours will differ)

| Kernel | Cycles per 256-sample window | Dominant stall |
| --- | --- | --- |
| fir16_low | ~1,300 | window lock (input wait) |
| fir16_high | ~1,350 | window lock |
| vec_add16 | ~300 | input lock (upstream compute) |

fir16_high is slightly longer by construction (32-deep history shift vs 16).
The adder mostly waits: it is the merge point of an unbalanced fork - a
dataflow imbalance made visible, and a natural discussion of window sizing
or kernel fusion.

## Representative NoC Results (labeled representative)

| Scenario | Class | Requested | Granted | Latency target/met |
| --- | --- | --- | --- | --- |
| A | best-effort | 1000 MB/s | >= requested, margin comfortable | no target |
| B | latency-critical | 2000 MB/s | met at higher latency budget cost | met, route changed |

The typical observable: scenario B's path takes a different physical route
(more/different hops) and the QoS report shows the latency-critical class
reserving buffer/bandwidth headroom - Section 7's "design-time allocation"
in report form.

## Common Failure Modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| x86sim cannot open data files | files not visible to run dir | copy data/ under Work/ run directory |
| Off-by-one LSB mismatch storm | golden model rounds once, not per half | mirror the graph's arithmetic |
| aiecompiler rejects connect fork | syntax/API drift across versions | use adf::connect form above; check the 2023.2 adf docs |
| NoC automation silent | CIPS defaults not applied | open axi_noc config, build NMU->MC0 path manually on connectivity tab |
| report_noc_qos empty | NoC compile not run | it executes during synthesis - run synthesis first |

## Conceptual Question Answers

1. Hardened NoC switching removes programmable-routing delay from the
interconnect; tile-local memory and stream connections remove the global
fabric from the datapath. Cost: fixed topology and memory sizes - you
configure rather than synthesize, so unusual structures do not fit.
2. Each window connection double-buffers: while a kernel computes on the
current buffer (ping), DMA fills the next (pong), so producer and consumer
overlap instead of alternating compute/wait.
3. Placement also honors connectivity locality (stream hops are expensive),
memory banking conflicts, port availability on the tile, and deadlock-free
scheduling - the ratio only certifies utilization headroom.
4. QoS lives in the NoC compiler's allocation of physical routes and
buffers at design time; renegotiation would require re-routing silicon
state that the platform deliberately fixes at compile time.

## Grading Notes

Full credit requires: both sims bit-exact, tile mapping and stall table from
the student's own run, both NoC scenario reports attached with the delta
discussed, and the Part 6 reflection using measured numbers from Labs 2 and
this lab.

---

**Presented by: Hossam Hassan, PhD**
