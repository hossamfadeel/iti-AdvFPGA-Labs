# Hands-On Labs: Advanced FPGA & Adaptive SoC Engineering

Companion lab series for the presentation **"Beyond the Basics -- Advanced FPGA &
Adaptive SoC Engineering"** (`presentations/Advanced_FPGA_Presentation/`). Each lab
extends one section of the deck from concepts into practice on the **AMD ZCU102
Evaluation Board** (XCZU9EG-2FFVB1156E, per UG1182), except Lab 7, which is a
deliberate toolflow-only exception.

## Lab Index

| Lab | File | Companion Section | Level | Hardware |
|-----|------|-------------------|-------|----------|
| 1 | [Lab01_DFX_Partial_Reconfiguration.md](./Lab01_DFX_Partial_Reconfiguration.md) | Section 1 -- Partial Reconfiguration & DFX | Advanced | ZCU102 |
| 2 | [Lab02_HLS_Optimization_Deep_Dive.md](./Lab02_HLS_Optimization_Deep_Dive.md) | Section 2 -- Vitis HLS Deep Dive | Intermediate | ZCU102 (estimates only) |
| 3 | [Lab03_AXI_DMA_Streaming.md](./Lab03_AXI_DMA_Streaming.md) | Section 3 -- Advanced AXI: Custom IP, DMA, Streams | Intermediate | ZCU102 |
| 4 | [Lab04_Cache_Coherency_HP_vs_HPC.md](./Lab04_Cache_Coherency_HP_vs_HPC.md) | Section 4 -- Cache Coherency + Zynq UltraScale+ MPSoC | Advanced | ZCU102 |
| 5 | [Lab05_Aurora_64B66B_SFP_Loopback.md](./Lab05_Aurora_64B66B_SFP_Loopback.md) | Section 5 -- PCIe + GT Transceivers | Advanced | ZCU102 + SFP+ DAC cable |
| 6 | [Lab06_Vitis_AI_DPU_Deployment.md](./Lab06_Vitis_AI_DPU_Deployment.md) | Section 6 -- DNN Acceleration on FPGA | Intermediate | ZCU102 + host PC (docker) |
| 7 | [Lab07_AIE_NoC_Simulation.md](./Lab07_AIE_NoC_Simulation.md) | Section 7 -- Versal ACAP: NoC & AI Engines | Advanced | **None** (simulation only) |
| 8 | [Lab08_TCL_Automated_Flows.md](./Lab08_TCL_Automated_Flows.md) | Section 8 -- Scripted Flows: TCL + CI/CD | Intermediate | ZCU102 (optional for bitstream) |

## The Lab Arc

Labs 2, 3, and 4 form a continuous thread: Lab 2 designs and optimizes an FIR
accelerator in Vitis HLS and packages it as an IP; Lab 3 wires it into a
PS-initiated streaming datapath (DDR -> AXI DMA -> FIR -> DDR) over a
non-coherent HP port; Lab 4 moves the same datapath to the coherent HPC port and
quantifies what cache coherency costs and saves. Lab 8 then shows how to turn any
of these builds into a scripted, CI-gated flow.

Lab 7 is the intentional outlier: the ZCU102 is an UltraScale+ MPSoC with no AI
Engine array and no hardened NoC, so the Section 7 companion is a Versal ACAP
**toolflow-and-simulation** exercise requiring no board.

## Board and Tool Baseline

- **Board**: ZCU102 Evaluation Board, rev 1.0 or later (UG1182)
- **Tools**: Vivado / Vitis / Vitis HLS **2023.2** baseline unless a lab states otherwise
- **Lab 6 pins Vitis AI 3.0** -- the last release with a pre-built ZCU102 board image
- **Serial console**: USB-UART on micro-USB **J83**, channel 0 (PS UART0), 115200 8N1
- **JTAG**: micro-USB **J2**
- Extra hardware per lab is listed in each lab's Prerequisites

## Solutions

Instructor solutions live in [solution/](./solution/). They contain expected
outputs, representative measurements, failure-mode debug trees, and full answers
to the conceptual questions.

---

**Presented by: Hossam Hassan, PhD**
