# Lab 7 — Versal AIE + NoC: Toolflow Without Hardware
**Companion to Section 7: Versal ACAP: NoC & AI Engines**
**Board:** None (Versal ACAP toolflow simulation; NOT possible on ZCU102) | **Level:** Advanced

---

## Introduction

Why no board: the ZCU102 is an UltraScale+ MPSoC. It has no AI Engine array
and no hardened NoC - those exist only on Versal ACAP silicon, which is the
architectural answer Section 7 gave to the limits Section 6 hit. This lab is
therefore deliberately toolflow-only: everything runs in Vitis and Vivado
2023.2 on your workstation, no bitstreams, no hardware purchase. What you
lose in blinking LEDs you gain in the two skills that transfer directly when
Versal hardware arrives: writing and reading an AIE graph (kernels, windows,
streams, tile placement), and configuring and evaluating a NoC (NMU/NSU,
traffic classes, requested-vs-granted bandwidth).

The compute vehicle is the same workload that has run through this whole
series, a 32-tap FIR - now expressed as an `adf::graph` of three kernels
split across AI Engine tiles, verified in x86 functional simulation, then
executed in cycle-approximate simulation and inspected through the compiler's
reports. The NoC half builds a minimal Versal design whose PS master reaches
the integrated DDR memory controller through one NMU and one NSU, and reads
what the NoC compiler grants versus what was requested under two QoS
scenarios. The closing exercise puts numbers on the heterogeneous-compute
claim: same FIR, soft logic (Labs 2-3) versus AIE tiles.

## Objectives

- Create an AI Engine design project in Vitis 2023.2 targeting a Versal AI Edge part.
- Implement a 32-tap FIR as an adf::graph with three kernels connected by window streams.
- Pass x86 functional simulation against a golden model, then run cycle-approximate aiesimulator.
- Read aiecompiler outputs: graph view, array view, kernel-to-tile mapping, stall and timing reports.
- Build a minimal Versal NoC design and compare requested vs granted bandwidth and latency across two traffic classes with report_noc_qos.
- Quantify soft-logic-versus-AIE tradeoffs for the same workload with your own recorded numbers.

## Prerequisites

- Vitis and Vivado 2023.2 with AI Engine tools installed; ~40 GB free disk.
- No board, no license-gated hardware targets (simulation only).
- Section 7 read: engines (scalar/adaptable/vector), NMU/NSU, NoC compiler, traffic classes, VLIW SIMD tiles, ping-pong buffering.

## Part 1: AI Engine Project

In Vitis 2023.2, create a component of type **AI Engine design** (File ->
New Component). When asked for a target, pick any **Versal AI Edge** device
offered by the part chooser - do not overthink the exact part; simulation
results do not depend on pin-level details, and hunting specifics in DS950 is
explicitly not required here. Note the family positioning from Section 7
(Premium/Prime/AI Edge/AI Core) in one line of your lab notes.

## Part 2: The FIR as an AIE Graph

The 32 taps split into two half-tap kernels plus a vector add - three
kernels, all `window<256>` int16 connections:

```cpp
// kernels.h
#ifndef __KERNELS_H__
#define __KERNELS_H__
#include <adf.h>
#include <window.hpp>

void fir16_low (adf::input_buffer<int16, adf::extents<256>>& in,
                adf::output_buffer<int16, adf::extents<256>>& out);
void fir16_high(adf::input_buffer<int16, adf::extents<256>>& in,
                adf::output_buffer<int16, adf::extents<256>>& out);
void vec_add16 (adf::input_buffer<int16, adf::extents<256>>& in0,
                adf::input_buffer<int16, adf::extents<256>>& in1,
                adf::output_buffer<int16, adf::extents<256>>& out);
#endif
```

```cpp
// kernels.cpp
#include "kernels.h"

static const int16 c_low[16]  = { 18,16,12, 8, 2,-4,-11,-18,
                                 -25,-31,-36,-40,-43,-44,-43,-40};
static const int16 c_high[16] = { -36,-30,-23,-15,-6, 3, 12, 20,
                                  27, 32, 35, 36, 34, 30, 24, 16};

void fir16_low(adf::input_buffer<int16, adf::extents<256>>& in,
               adf::output_buffer<int16, adf::extents<256>>& out) {
  static int16 hist[16] = {0};
  auto* xi = in.data();  auto* yo = out.data();
  for (unsigned n = 0; n < 256; n++) {
    for (unsigned k = 15; k > 0; k--) hist[k] = hist[k-1];
    hist[0] = xi[n];
    int32 acc = 0;
    for (unsigned k = 0; k < 16; k++) acc += (int32)c_low[k] * hist[k];
    yo[n] = (int16)(acc >> 15);            /* Q15 per-half rounding */
  }
}

void fir16_high(adf::input_buffer<int16, adf::extents<256>>& in,
                adf::output_buffer<int16, adf::extents<256>>& out) {
  static int16 hist[32] = {0};             /* taps 16..31 need deeper history */
  auto* xi = in.data();  auto* yo = out.data();
  for (unsigned n = 0; n < 256; n++) {
    for (unsigned k = 31; k > 0; k--) hist[k] = hist[k-1];
    hist[0] = xi[n];
    int32 acc = 0;
    for (unsigned k = 16; k < 32; k++) acc += (int32)c_high[k-16] * hist[k];
    yo[n] = (int16)(acc >> 15);
  }
}

void vec_add16(adf::input_buffer<int16, adf::extents<256>>& in0,
               adf::input_buffer<int16, adf::extents<256>>& in1,
               adf::output_buffer<int16, adf::extents<256>>& out) {
  auto* a = in0.data(); auto* b = in1.data(); auto* y = out.data();
  for (unsigned n = 0; n < 256; n++) y[n] = a[n] + b[n];
}
```

The graph forks the input to both half-taps and merges through the adder:

```cpp
// graph.h
#ifndef __FIR_GRAPH_H__
#define __FIR_GRAPH_H__
#include <adf.h>
#include "kernels.h"

class fir_graph : public adf::graph {
private:
  adf::kernel k_low, k_high, k_add;
public:
  adf::input_port  in;
  adf::output_port out;
  fir_graph() {
    k_low  = adf::kernel::create(fir16_low);
    k_high = adf::kernel::create(fir16_high);
    k_add  = adf::kernel::create(vec_add16);
    adf::connect<adf::window<256>> (in,           k_low.in[0]);
    adf::connect<adf::window<256>> (in,           k_high.in[0]);
    adf::connect<adf::window<256>> (k_low.out[0], k_add.in[0]);
    adf::connect<adf::window<256>> (k_high.out[0],k_add.in[1]);
    adf::connect<adf::window<256>> (k_add.out[0], out);
    adf::source(k_low)  = "kernels.cpp";
    adf::source(k_high) = "kernels.cpp";
    adf::source(k_add)  = "kernels.cpp";
    adf::runtime<ratio>(k_low)  = 0.1;
    adf::runtime<ratio>(k_high) = 0.1;
    adf::runtime<ratio>(k_add)  = 0.1;
  }
};
#endif
```

```cpp
// graph.cpp - files -> graph -> files testbench
#include <adf.h>
#include "graph.h"

fir_graph filter;
adf::PLIO* in_file  = adf::PLIO::create("in",  adf::plio_32_bits, "data/input.txt");
adf::PLIO* out_file = adf::PLIO::create("out", adf::plio_32_bits, "data/output.txt");

int main(void) {
  filter.in  = *(in_file->master[0]);
  filter.out = *(out_file->slave[0]);
  filter.init();
  filter.run(4);          /* 4 iterations: 1024 samples through the graph */
  filter.end();
  return 0;
}
```

Generate `data/input.txt` (1024 lines, one int16 per line - an impulse or an
LCG sequence) and a golden `golden.txt` with a script that applies **the same
per-half truncation** as the kernels:

```python
# golden.py - mirrors the graph's fixed-point partitioning exactly
c_low  = [18,16,12,8,2,-4,-11,-18,-25,-31,-36,-40,-43,-44,-43,-40]
c_high = [-36,-30,-23,-15,-6,3,12,20,27,32,35,36,34,30,24,16]
x = [((s*1664525+1013904223) >> 16) % 2000 - 1000 for s in range(1024)]
h_lo, h_hi = [0]*16, [0]*32
for n in range(1024):
    for k in range(15, 0, -1): h_lo[k] = h_lo[k-1]
    for k in range(31, 0, -1): h_hi[k] = h_hi[k-1]
    h_lo[0] = h_hi[0] = x[n]
    lo = sum(c_low[k]*h_lo[k] for k in range(16)) >> 15
    hi = sum(c_high[k-16]*h_hi[k] for k in range(16, 32)) >> 15
    print(lo + hi)
```

(The rounding split per half is not cosmetic: graph partitioning and
fixed-point quantization interact, and your golden model must model the
graph's arithmetic, not the unpartitioned filter's.)

## Part 3: x86 Functional Simulation

Build the x86Sim configuration and run it (GUI: build then run; CLI pattern,
paths simplified):

```
aiecompiler --target=x86sim graph.cpp     # produces ./Work
x86simulator --pkg-dir=Work
```

Diff `output.txt` against `golden.txt` - bit-exact or find out why. If the
simulator cannot find the data files, copy `data/` next to the simulator run
directory under `Work/`.

## Part 4: Cycle-Approximate Simulation and Compiler Reports

Retarget and rerun:

```
aiecompiler --target=aiesim graph.cpp
aiesimulator --pkg-dir=Work
```

Verify output again, then dig into what the compiler decided, in Vitis
Analyzer (the reports open from the component's summary):

1. **Graph view:** three kernels, the fork at `in`, the merge at `k_add` -
   your connectivity, now physical.
2. **Array view:** each kernel sits on its own AIE tile with coordinates
   (col,row); record the mapping. Double-buffered window buffers (the
   ping-pong scheme from Section 7) appear per consumer port.
3. **Trace/timing:** with trace enabled on the aiesim run, the analyzer
   shows per-kernel execution cycles and stall reasons (lock, stream,
   memory). Record each kernel's cycle count and dominant stall.
4. **Runtime ratios:** with ratio 0.1 the compiler may co-locate kernels;
   note whether it did and why that is legal (ratio < 1 means a tile has
   slack - Section 7's tile-sharing story).

## Part 5: Minimal NoC in Vivado

1. New Vivado 2023.2 project, any Versal AI Edge part from the chooser.
2. Create a block design; add the **CIPS (Versal)** IP and take defaults;
   add the **AXI NoC** IP. Use **Run Block Automation** on the NoC to create
   one NMU fed by the PS and one NSU attached to the integrated DDR memory
   controller (MC0). If automation does not prompt, open the AXI NoC
   customization and build the same one-path topology on its connectivity
   tab. You have just drawn the NMU/NSU picture from Section 7 - initiators
   enter at NMUs, targets live behind NSUs, and the switched middle is the
   hardened fabric you configure rather than synthesize.
3. **QoS scenario A (best effort):** in the NoC QoS settings, set the
   PS-to-MC0 path to best-effort with a moderate requested bandwidth (for
   example 1000 MB/s read). Run synthesis (the NoC compiler executes as part
   of it), then:

```tcl
open_run synth_1
report_noc_qos         -file reports/noc_qos_A.rpt
report_noc_connectivity -file reports/noc_conn_A.rpt
```

4. **QoS scenario B (latency critical):** change the same path to the
   latency-critical class with a tighter latency target and a higher
   requested bandwidth, re-run, and regenerate the reports.
5. **Read both:** for each scenario record requested vs granted/achievable
   bandwidth and latency, and find the physical route (hop count,
   vertical/horizontal links) each path takes in the connectivity report and
   the NoC view of the device. Note what the NoC compiler traded when the
   demand went up - Section 7's point that QoS is allocated at design time,
   not negotiated at runtime.

## Part 6: Same Workload, Two Engines

Build the comparison table with your own numbers: the FIR as soft logic
(Lab 2's V3 resource report) versus this lab's AIE mapping (three tiles,
per-kernel cycles from trace):

| Metric | Soft logic (Lab 2 V3) | AIE tiles (this lab) |
| --- | --- | --- |
| Compute resource | DSP/LUT count | 3 tiles (+ shim/stream) |
| Effective rate | samples/s at 150 MHz | samples/s from trace |
| Design effort | pragmas + reports | graph + reports |

Write five lines of reflection: which engine you would choose for a
128-tap FIR at high sample rate, and what Section 7's "right engine per
workload" predicts - control to the scalar core, MAC-dense math to vector
engines, neither to LUTs unless it must be there.

## Verification Checkpoints

| Checkpoint | Target | Method |
| --- | --- | --- |
| x86 sim | bit-exact vs golden.txt | diff |
| aiesim | output still matches | diff after re-run |
| Tile mapping recorded | 3 kernels -> distinct tiles with coordinates | array view |
| Stall/timing recorded | per-kernel cycles + dominant stall | trace in analyzer |
| NoC scenario A | requested vs granted recorded | report_noc_qos |
| NoC scenario B | delta vs A recorded and explained | report_noc_qos |
| Reflection table | filled with real numbers | Part 6 |

**Quantitative targets:** zero mismatches in both simulations; per-kernel
cycle counts and stall breakdown captured; NoC granted bandwidth meeting or
exceeding request in scenario A, and a recorded, explained latency/bandwidth
delta between traffic classes in scenario B.

## Conceptual Questions

1. Section 7's wall is wire delay. Name two concrete mechanisms in this lab
that answer it (hardened switching, tile-local memory/streams) and one thing
they cost you relative to soft logic.
2. The graph uses window<256> connections rather than raw streams. Explain
the ping-pong double buffering the runtime applies to those windows and why
that keeps kernels overlapped.
3. Your runtime ratios are 0.1 but the compiler still placed kernels on
separate tiles. What information, beyond the ratio, drives placement?
4. In the NoC lab, requested bandwidth was met in one scenario and the
latency-critical scenario changed the route. What does this tell you about
where QoS is enforced - and why that is incompatible with runtime
renegotiation?

---

**Presented by: Hossam Hassan, PhD**
