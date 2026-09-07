# ITI Advanced FPGA Labs

**Information Technology Institute (ITI), Egypt** -- Advanced FPGA & Adaptive
SoC Engineering Workshop

Eight hands-on labs for the Zynq UltraScale+ MPSoC (ZCU102 / Kria KR260):
Dynamic Function eXchange, Vitis HLS optimization, AXI DMA streaming, cache
coherency (HP vs HPC), Aurora 64B/66B on SFP+, Vitis AI DPU, AIE/NoC, and
scripted TCL flows. Companion project repository:
[iti-advFPGA-capstone](https://github.com/hossamfadeel/iti-advFPGA-capstone)
(Spectrum Sentry -- the same methodology at full system scale).

## Repository layout

| Path | Contents |
|------|----------|
| `Lab0*_*.md` | The eight lab handouts (start here) |
| `INDEX.md` | Lab index / ordering / prerequisites |
| `solution/` | Answer keys (`LabXX_Solution.md`), step-by-step guides (`LabXX_Solution_StepByStep.md`), and runnable scripts |
| `solution/run_all.sh` | Master runner: executes every machine-verifiable lab |
| `solution/scripts/labXX_*/` | Per-lab code, TBs, TCL flows, run scripts |

## Solution status (verified on AMD tools 2025.2, Windows, no board)

`./solution/run_all.sh` -- current result: **4 PASS, 0 FAIL** (labs 01, 02, 05, 08)

| Lab | Machine-verified here | What ran | Needs |
|-----|----------------------|----------|-------|
| 01 DFX | **PASS** | Behavioral TB (xsim) AND **full DFX implementation flow on both KR260 (xck26) and ZCU102 (xczu9eg)**: 2 full + 2 partial bitstreams per board, `pr_verify` clean, partials byte-identical in size across RMs | board only for live swap |
| 02 HLS | **PASS** | All four variants (V0-V3) csim (impulse + LCG vs golden) + csynth; measured DSE table (V3 = 236x faster) | -- |
| 03 AXI DMA | bench | Complete bare-metal app (no ellipses) + BD + throughput harness | ZCU102 bench |
| 04 Coherency | bench | Parts 1-3 staged code (break/fix/price, HPC0) | ZCU102 bench |
| 05 Aurora | **PASS** | BERT logic in sim: 2002 words, injected corruption detected (2 error events), clean relock | board for GT soak |
| 06 Vitis AI | bench | VART app + docker compile + board scripts | board + Docker |
| 07 AIE/NoC | tool | Complete graph code + exact flow | workstation with aiecompiler |
| 08 TCL | **PASS** | Real Vivado batch synth + WNS gate + CI example | -- |

## Running the solutions

```bash
cd solution
./run_all.sh                       # everything machine-verifiable
# or individually:
./scripts/lab01_dfx/run_sim.sh                      # xsim
vivado -mode batch -source scripts/lab01_dfx/dfx_build.tcl -tclargs kr260
./scripts/lab02_hls/run.sh all                      # csim+csynth x4 (vitis-run)
./scripts/lab05_aurora/run_sim.sh                   # xsim BERT
./scripts/lab08_tcl/run_gate_test.sh                # vivado synth + WNS gate
```

Tool root defaults to `C:\AMDDesignTools\2025.2` -- override with the
`AMD_TOOLS` environment variable. Generated artifacts (bitstreams, HLS
projects, xsim libs) land in `build/` trees and are gitignored.

## Teaching notes embedded in the solutions

Every step-by-step guide documents the issues found while actually running
the flows -- KEEP_HIERARCHY on RMs, GT-bank traps in pin selection, BERT
state-adoption semantics, wrong-loop pipelining, DRC HDPR I/O clipping --
because debugging these IS the lab.
