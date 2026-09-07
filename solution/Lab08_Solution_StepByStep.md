# Lab 08 -- TCL Automated Flows: Step-by-Step Solution

**TESTED on this workstation (2025.2): scripted synth + WNS gate PASS.**

## What was actually run (and passed)
`scripts/lab08_tcl/run_gate_test.sh`
-> `vivado -mode batch -source build.tcl -tclargs synth` (real synth,
reports written) -> `gates/wns_gate.tcl` -> `PASS: all timing clean`.

## Step-by-step

### Part 1: repository structure
The lab's tree, materialized: `rtl/ constr/ scripts/ reports/ Makefile`;
the solution keeps `tiny/` as the design under flow.

### Part 2: the build script
`build.tcl` -- non-project, step-parameterized:
read RTL -> read XDC -> synth -> checkpoint+reports (synth);
open checkpoint -> opt/place/phys_opt/route -> reports -> WNS GATE ->
bitstream (impl). One source of truth: no GUI state anywhere.

### Part 3: the Makefile
`make synth / impl / reports / clean` wrapping the TCL -- clean-clone
discipline (the capstone repo runs the identical pattern at full scale).

### Part 4: the gate -- and proving it bites
`gates/wns_gate.tcl` parses WNS from the timing report and `exit 1` on
violation. Proof method (run it once): temporarily tighten the clock in
`tiny/constr/top.xdc` to an impossible period; the gate FAILS the build.
That is the demo that the gate is load-bearing, not decoration.

### Part 5: CI
`ci_example.yml`: self-hosted runner with Vivado, one step --
`./run_gate_test.sh` -- artifact-upload of reports. The tested script IS
the CI payload; nothing new needs to work "only on the runner".

### Part 6: reproducibility discipline
- Reports and checkpoints are OUTPUTS (gitignored); inputs are code.
- The regression gates print PASS/FAIL lines -- grep-able by humans and
  CI alike (same convention as every lab in this solution set).
