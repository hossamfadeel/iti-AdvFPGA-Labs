# Lab 01 -- DFX Partial Reconfiguration: Step-by-Step Solution

**Tested on this workstation (2025.2):** behavioral DFX verification PASS.
**Board required for:** Vivado DFX bitstream generation + PCAP swap (script provided).

## What was actually run (and passed)
`scripts/lab01_dfx/run_sim.sh` -> `PASS: tb_dfx_behavior`
Covers: decoupler safe-value behavior, RM reset sequencing, static heartbeat
continuity across the swap window (162 cycles counted during a simulated
partial reconfiguration).

## Step-by-step

### Part 1-2: static + RMs
1. `scripts/lab01_dfx/rtl/heartbeat_ctr.sv` -- free-running 32-bit counter.
   Pitfall found while testing: `initial count = 0;` on an `always_ff`
   variable is a dual-driver error in xsim -- initialize a separate
   internal register and drive the output through `assign`.
2. `pattern_chaser.sv` / `pattern_lfsr.sv` -- identical interfaces (this is
   what makes them swappable RMs).

### Behavioral gate (runs before any synthesis)
3. `tb/tb_dfx_behavior.sv` (from the lab, one correction): the lab's
   `hb_count > 200` check is unreachable in the lab's own 1620 ns timeline
   (~162 cycles max) -- the solution fixes the threshold to 150 and notes
   it. Assertions: LEDs dark while decoupled, no glitch at the boundary,
   heartbeat monotonic through the reconfig window.
4. Run: `./run_sim.sh` (xvlog -> xelab -> xsim, PASS-gated).

### Parts 3-5: Vivado DFX flow (scripted, `dfx_build.tcl`)
5. One command produces everything: `vivado -mode batch -source dfx_build.tcl`
   - config A synth -> `set_property HD.RECONFIGURABLE 1 [get_cells u_pattern]`
   - pblock `CLOCKREGION_X1Y2`, CONTAIN_ROUTING true
   - impl -> full + partial bitstreams
   - config B: `synth_design -mode out_of_context` RM-B, `read_checkpoint
     -cell`, stitch into frozen static, `pr_verify`, full + partial
6. Expected observation (record sizes): the two partials are nearly
   identical in size and a small fraction of the full bitstream -- size is
   a floorplan (pblock) property, not a logic-content property.

### Part 6: PCAP swap from the PS
Board: boot the A53 app, `fpga_manager` load of `partial_*.bit` with
`flags=1` (partial), bracketed by decouple assert -> rm reset -> load ->
release. The behavioral TB is the pre-board contract for that sequence.

## Deliverables map
rtl/, tb/, run_sim.sh (TESTED), dfx_build.tcl + dfx_top.xdc (complete flow).
