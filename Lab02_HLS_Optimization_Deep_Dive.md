# Lab 2 — Vitis HLS Deep Dive: FIR Optimization Study
**Companion to Section 2: Vitis HLS Deep Dive**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Introduction

Section 2 showed that Vitis HLS turns untimed C into timed RTL through
scheduling, binding, and allocation, with pragmas entering as hard constraints
on those steps. It also claimed that a pragma change plus a csynth rerun takes
minutes, while the same exploration in RTL means rewriting the pipeline. This
lab is where you cash that claim in. You will take one fixed kernel, a 128-tap
direct-form FIR, and drive it through four solutions (V0 through V3) using
only the pragmas Section 2 covered: PIPELINE, DATAFLOW, UNROLL, and
ARRAY_PARTITION, with the interface pragmas fixed from the start so the IP is
ready for the block design in Lab 3.

Every number you need comes from your own schedule reports - Section 2
insisted the schedule report is read before cosim, and here you will read four
of them and fill a measured tradeoff table (II, latency, DSP48E2, LUT, BRAM
per variant). The lab closes by exporting the best variant as `fir_hls_ip`
for the Vivado IP catalog. That package is the deliverable handed forward:
Lab 3 wires it into a ZCU102 block design with an AXI DMA, and Lab 4 moves
the same IP onto a coherent HPC port. Nothing in those labs works unless this
export succeeds.

No board is required today. Everything runs on your workstation; the ZCU102
part (`xczu9eg-ffvb1156-2-e`) is set as the target so resource estimates are
real for the device you will meet in Lab 3.

## Objectives

- Build a Vitis HLS 2023.2 project for a 128-tap FIR with AXI4-Stream sample ports and AXI4-Lite control (ap_ctrl_hs).
- Validate the kernel in csim against a plain-C golden model, using impulse-response equality as the self-check.
- Synthesize four pragma variants (V0..V3) and read their schedule reports quantitatively.
- Diagnose what limits II at each step using the target-vs-achieved columns and the dataflow viewer.
- Fill a measured tradeoff table (II, latency, DSP48E2, LUT, BRAM_18K) and compare against ZCU102 device totals.
- Pass C/RTL cosimulation and export the best variant as `fir_hls_ip` for reuse in Labs 3 and 4.

## Prerequisites

- Vitis HLS 2023.2 installed (`vitis_hls` on PATH); free edition is sufficient.
- Comfort with the C from Section 2's code slides: fixed-size arrays, loops, no dynamic memory.
- No ZCU102 hardware needed until Lab 3; the part string is used only for synthesis targets.

## Part 1: Project Setup and C Simulation

Create `lab02_fir/` with `fir.h`, `fir.cpp`, `fir_tb.cpp`, and `run_hls.tcl`.
`fir.h` fixes the types, the block size, and the coefficient ROM:

```cpp
#ifndef FIR_H
#define FIR_H
#include <stdint.h>
#include <hls_stream.h>

#define TAPS     128
#define SAMPLES  1024          // one block per ap_start pulse

typedef int16_t data_t;        // input samples
typedef int16_t coef_t;        // ROM coefficients
typedef int32_t acc_t;         // accumulator

/* 128-tap low-pass, Hamming window, fc = Fs/4 (any fixed set works;
   impulse-response self-check holds for whatever you choose) */
static const coef_t FIR_COEF[TAPS] = {
  -18,-16,-12, -8, -2,  4, 11, 18, 25, 31, 36, 40, 43, 44, 43, 40,
   36, 30, 23, 15,  6, -3,-12,-20,-27,-32,-35,-36,-34,-30,-24,-16,
   -8,  0,  9, 16, 22, 26, 28, 28, 26, 22, 16,  9,  1, -7,-14,-19,
  -23,-24,-23,-20,-16,-10, -4,  3,  9, 14, 18, 20, 21, 19, 16, 12,
    6,  0, -5, -9,-12,-13,-12,-10, -7, -3,  0,  3,  6,  8,  9,  9,
    8,  6,  4,  1, -1, -4, -6, -7, -8, -8, -7, -5, -3,  0,  1,  3,
    5,  6,  6,  6,  5,  4,  2,  0, -1, -3, -4, -5, -5, -5, -4, -3,
   -2,  0,  1,  2,  3,  3,  3,  3,  2,  1,  0, -1, -1, -2, -2, -2
};
#endif
```

The testbench holds two checks: an impulse (output must equal the coefficient
set, the clean self-check Section 2 advocated) and an LCG random block against
an independently written plain-C golden model:

```cpp
#include "fir.h"
#include <stdio.h>

static acc_t golden_ref(data_t hist[TAPS], data_t xn) {
  for (int i = TAPS - 1; i > 0; --i) hist[i] = hist[i - 1];
  hist[0] = xn;
  acc_t acc = 0;
  for (int i = 0; i < TAPS; ++i) acc += (acc_t)hist[i] * FIR_COEF[i];
  return acc;
}

static uint32_t lcg(void) {
  static uint32_t s = 0x12345678u;
  s = s * 1664525u + 1013904223u;  return s;
}

int main() {
  hls::stream<data_t> in("in");  hls::stream<acc_t> out("out");
  data_t stim[SAMPLES];  data_t hist[TAPS] = {0};  int fail = 0;

  in.write(1);                                    /* Test 1: impulse */
  for (int i = 1; i < SAMPLES; ++i) in.write(0);
  fir_top(in, out);
  for (int i = 0; i < SAMPLES; ++i) {
    acc_t exp = (i < TAPS) ? (acc_t)FIR_COEF[i] : 0;
    if (out.read() != exp && ++fail < 8) printf("IMPULSE FAIL %d\n", i);
  }
  printf("Test 1 (impulse): %s\n", fail ? "FAIL" : "PASS");

  for (int i = 0; i < SAMPLES; ++i) stim[i] = (data_t)(lcg() >> 16);
  for (int i = 0; i < SAMPLES; ++i) in.write(stim[i]);   /* Test 2 */
  fir_top(in, out);
  for (int i = 0; i < SAMPLES; ++i)
    if (out.read() != golden_ref(hist, stim[i]) && ++fail < 8)
      printf("RANDOM FAIL %d\n", i);
  printf("Test 2 (random vs golden): %s\n", fail ? "FAIL" : "PASS");
  return fail ? 1 : 0;
}
```

Note the kernel's sample history is a local array initialized each call (not
`static`) so the second `fir_top` call starts from a clean state -
deterministic testbench, exactly the discipline Section 2 demanded.

## Part 2: V0 Baseline Synthesis

`fir.cpp` starts with interface pragmas only (they are part of the contract
with Lab 3, not performance knobs):

```cpp
#include "fir.h"

void fir_top(hls::stream<data_t>& in, hls::stream<acc_t>& out) {
#pragma HLS INTERFACE axis port=in
#pragma HLS INTERFACE axis port=out
#pragma HLS INTERFACE s_axilite port=return
    data_t x[TAPS] = {0};
    const coef_t* c = FIR_COEF;
    MAC: for (int n = 0; n < SAMPLES; ++n) {
        data_t xn = in.read();
        SHIFT: for (int i = TAPS - 1; i > 0; --i) x[i] = x[i - 1];
        x[0] = xn;
        acc_t acc = 0;
        TAP: for (int i = 0; i < TAPS; ++i)
            acc += (acc_t)x[i] * c[i];
        out.write(acc);
    }
}
```

Drive everything from one script so the build-and-measure loop is one command:

```tcl
# run_hls.tcl - vitis_hls -f run_hls.tcl -tclargs <v0|v1|v2|v3>
set SOL v0
if {$argc > 0} { set SOL [lindex $argv 0] }
open_project fir_proj            ;# add -reset on the first run only
set_top fir_top
add_files fir.cpp
add_files -tb fir_tb.cpp
open_solution $SOL -flow_target vivado
set_part xczu9eg-ffvb1156-2-e
create_clock -period 6.667       ;# 150 MHz
csim_design
csynth_design
cosim_design -trace_level none
if {$SOL eq "v3"} { export_design -format ip_catalog -rtl verilog }
exit
```

Run `vitis_hls -f run_hls.tcl -tclargs v0` (GUI users: same files through the
wizard). Then read `fir_proj/solutions/v0/syn/report/fir_top_csynth.rpt`:
find the function and loop latencies, and the resource table. Open the
Schedule Viewer and confirm what Section 2's triage row predicts for a
latency far above the trip count: the SHIFT iterations run sequentially, and
the TAP iterations serialize on the acc loop-carried dependency. Fill row V0
of the table in Part 5.

## Part 3: V1 - Pipelining and What Limits II

Copy the solution as `v1` and add one line inside the TAP loop:

```cpp
        TAP: for (int i = 0; i < TAPS; ++i) {
#pragma HLS PIPELINE II=1
            acc += (acc_t)x[i] * c[i];
        }
```

Re-run and read the report's Target II vs Achieved II for TAP. At 150 MHz the
int32 accumulate recurrence closes in one cycle, so II=1 is achievable. Now
the lesson: block latency barely halves, because the SHIFT loop is still
sequential and the outer MAC loop is not pipelined - nested loops nest time.
This variant exists to make that wall visible before V3 removes it.

## Part 4: V2 - Dataflow and the Dataflow Viewer

Restructure `fir.cpp` into three processes with stream channels (keep the V1
pipeline pragma inside compute):

```cpp
static void load(hls::stream<data_t>& in, hls::stream<data_t>& s) {
LOAD: for (int n = 0; n < SAMPLES; ++n) s.write(in.read());
}

static void compute(hls::stream<data_t>& s, hls::stream<acc_t>& r) {
    data_t x[TAPS] = {0};
    const coef_t* c = FIR_COEF;
LOOP_SAMPLE: for (int n = 0; n < SAMPLES; ++n) {
        data_t xn = s.read();
    SHIFT: for (int i = TAPS - 1; i > 0; --i) x[i] = x[i - 1];
        x[0] = xn;
        acc_t acc = 0;
    TAP: for (int i = 0; i < TAPS; ++i) {
#pragma HLS PIPELINE II=1
            acc += (acc_t)x[i] * c[i];
        }
        r.write(acc);
    }
}

static void store(hls::stream<acc_t>& r, hls::stream<acc_t>& out) {
STORE: for (int n = 0; n < SAMPLES; ++n) out.write(r.read());
}

void fir_top(hls::stream<data_t>& in, hls::stream<acc_t>& out) {
#pragma HLS INTERFACE axis port=in
#pragma HLS INTERFACE axis port=out
#pragma HLS INTERFACE s_axilite port=return
#pragma HLS DATAFLOW
    static hls::stream<data_t> s("s");
    static hls::stream<acc_t>  r("r");
#pragma HLS STREAM variable=s depth=4
#pragma HLS STREAM variable=r depth=4
    load(in, s);  compute(s, r);  store(r, out);
}
```

Open the dataflow viewer after csynth: load, compute, and store run
concurrently, connected by FIFO channels. Verify the single-producer
single-consumer rule: every token flows unconditionally, so no deadlock is
possible. Expect a small latency gain only - compute dominates - which is
exactly the shape Section 2's conv2d table showed for DATAFLOW: it buys the
last ten percent, not the first tenfold.

## Part 5: V3 - Partition and Unroll: the Resource-Throughput Tradeoff

Copy to `v3` and make the compute process fully parallel:

```cpp
static void compute(hls::stream<data_t>& s, hls::stream<acc_t>& r) {
    data_t x[TAPS] = {0};
#pragma HLS ARRAY_PARTITION variable=x complete dim=1
    const coef_t* c = FIR_COEF;
LOOP_SAMPLE: for (int n = 0; n < SAMPLES; ++n) {
#pragma HLS PIPELINE II=1
        data_t xn = s.read();
    SHIFT: for (int i = TAPS - 1; i > 0; --i) x[i] = x[i - 1];
        x[0] = xn;
        acc_t acc = 0;
    TAP: for (int i = 0; i < TAPS; ++i) {
#pragma HLS UNROLL factor=TAPS
            acc += (acc_t)x[i] * c[i];
        }
        r.write(acc);
    }
}
```

and immediately after `#include "fir.h"` in `fir.cpp` (so it binds to the
header-declared ROM):

```cpp
#pragma HLS ARRAY_PARTITION variable=FIR_COEF complete
```

UNROLL and ARRAY_PARTITION travel together, as Section 2 stressed: 128
parallel MACs need 128 coefficient reads per cycle, which a BRAM-backed
array cannot supply until it is partitioned into registers. Record the
resource jump: DSP48E2 count should land in the vicinity of the tap count -
one multiplier per tap - against a device total of 2,520 on the XCZU9EG.
Fill the measured table:

| Variant | Hot-loop II | Block latency (cycles) | DSP48E2 | LUT | BRAM_18K | % DSP of 2,520 |
| --- | --- | --- | --- | --- | --- | --- |
| V0 | n/a (sequential) |  |  |  |  |  |
| V1 | (TAP) |  |  |  |  |  |
| V2 | (TAP) |  |  |  |  |  |
| V3 | (LOOP_SAMPLE) |  |  |  |  |  |

## Part 6: Cosimulation and IP Export

The run script already cosimulates every variant; confirm each `*_cosim.rpt`
says PASS and compare V3's cosim latency against its csynth estimate (they
should agree within a few percent). Then export V3:

```tcl
if {$SOL eq "v3"} { export_design -format ip_catalog -rtl verilog }
```

Locate `fir_proj/fir_hls_ip_sol/impl/ip/` after export (the IP takes the top
function's name) and inspect the generated control: with `s_axilite
port=return` and no scalar arguments, the register map is a single control
register at offset 0x00 - ap_start bit 0, ap_done bit 1, ap_idle bit 2,
ap_ready bit 3. Lab 3's PS code writes 0x1 and polls bit 1; that is the whole
driver contract. Import the zip into your Vivado IP catalog once, so Lab 3
starts from a known state.

## Verification Checkpoints

| Checkpoint | Target | Method |
| --- | --- | --- |
| csim golden match | impulse y[i] == FIR_COEF[i]; random bit-exact vs golden | Test 1/2 PASS, exit code 0 |
| csynth all variants | table row filled, achieved II recorded | csynth reports |
| V1/V3 achieved II | 1 for TAP (V1) and LOOP_SAMPLE (V3) | report Interval columns |
| Dataflow overlap | load/compute/store concurrent in viewer | V2 dataflow graph |
| cosim all variants | PASS, latency within ~5% of csynth | cosim reports |
| IP export | fir_hls_ip importable into Vivado IP catalog | import + instantiate |

**Quantitative targets:** block latency strictly decreasing V0 to V1 to V2 to
V3 in your table; V3 hot-loop achieved II = 1; V3 DSP count within a small
factor of TAPS (record exact) yet under 10% of the 2,520 DSP48E2 available;
impulse equality exact; every cosim PASS.

## Conceptual Questions

1. V1 pipelines the TAP loop to II=1 yet the block still needs hundreds of
cycles per sample. Name the two structures that bound sample rate besides the
MAC recurrence, and state how V3 removes each.
2. Suppose you had added `UNROLL factor=TAPS` in V3 without the ARRAY_PARTITION
pragmas. Using Section 2's triage table, what does the report show, and which
resource row proves the diagnosis?
3. The V2 channels are FIFOs with single producers and consumers. What
property of `compute` guarantees no token is ever skipped or duplicated, and
what would you see in simulation if a future edit broke that property?
4. Given your measured V3 numbers on this device: could you double the sample
throughput again on the same XCZU9EG? Which resource saturates first, and what
pragma change (with what cost) would get you there?

---

**Presented by: Hossam Hassan, PhD**
