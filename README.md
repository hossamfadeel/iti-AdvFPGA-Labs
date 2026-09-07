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

## Solution status

**All 8 labs are solved**: every lab has complete solution artifacts (code,
TBs, TCL flows), a step-by-step guide (`solution/LabXX_Solution_StepByStep.md`),
and an answer key. Of those, **4 are machine-verified** on this toolchain
(AMD tools 2025.2, Windows, no board) and **4 are bench/tool-bound by nature**
-- complete, but they require hardware or tools this workstation does not
have.

`./solution/run_all.sh` -- current result: **4 PASS, 0 FAIL**

### Machine-verified here (4 of 8)

| Lab | What ran | Evidence |
|-----|----------|----------|
| 01 DFX | Behavioral TB (xsim) AND **full DFX implementation flow on BOTH boards** -- `vivado -mode batch -source dfx_build.tcl -tclargs kr260\|zcu102` | RC:0 both; 2 full + 2 partial bitstreams per board; `pr_verify` "Verification completed successfully" x2; partials byte-identical in size across RMs (KR260: 677,900 B, ZCU102: 1,000,861 B) -- partial size is a pblock property (8.7% / 3.8% of full) |
| 02 HLS | All four variants (V0-V3) csim (impulse + LCG vs golden) + csynth via `vitis-run` | All PASS; measured DSE table (V3 = 236x faster, II 275589 -> 1166) |
| 05 Aurora | BERT logic in simulation (framer -> elastic channel -> checker) | 2002 words, injected corruption detected as exactly 2 error events (state-adoption semantics), clean relock |
| 08 TCL | Real Vivado batch synth + WNS gate + CI example | `SYNTH DONE` + `PASS: all timing clean` |

> KR260/ZCU102 DFX caveat: the offline flow uses auto-selected valid PL-bank
> pins (flow validation). The bench run substitutes the real carrier
> constraints -- ZCU102 master XDC / K26 SOM **XTP685** -- one clearly
> marked file.

### Complete artifacts, bench/tool-bound (4 of 8)

| Lab | Why not executed here | What is ready |
|-----|----------------------|---------------|
| 03 AXI DMA | needs the ZCU102 platform on hardware | complete bare-metal `main.c` (zero ellipses), BD wiring table, throughput harness (4K/64K/1M), Part-5 disconnect predictions |
| 04 Coherency | needs the Lab03 platform on hardware | parts 1-3 staged code (deterministic break / restore+price / HPC0 via CCI), maintenance timing loop |
| 06 Vitis AI | needs board + Docker | minimal VART app, docker `vai_q`/`vai_c` compile script, board run script |
| 07 AIE/NoC | `aiecompiler`/`aiesimulator` **verified absent** from the unified Vitis 2025.2 install on the reference workstation | complete 4-tile polyphase FIR graph (`adf`), impulse self-check stimulus, exact command flow |

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
