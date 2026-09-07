# Lab 8 — Scripted Flows: TCL Builds and CI/CD
**Companion to Section 8: Scripted Flows: TCL + CI/CD**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Introduction

Section 8 argued that the GUI is for exploration and the script is for
production: non-project mode makes every build step explicit and diffable,
checkpoints make every stage resumable, report gates make quality
machine-checkable, and CI makes all of it someone else's scheduled problem.
This lab converts that argument into a working repository. The design under
test is deliberately trivial - a two-LED chaser in SystemVerilog - because
the deliverable is not the bitstream, it is the flow: one command from clean
clone to gated bitstream, red CI on a broken constraint, green on the fix,
and a git hash baked into the bitstream as proof of provenance.

The flow is board-real (part `xczu9eg-ffvb1156-2-e`, LED pins AG14 and AL12
in bank 44) but does not require the board: CI verifies timing and produces
artifacts; programming the device is an optional last step. An optional
exercise swaps in the Lab 2/3 accelerator design as the DUT, at which point
your DFX/HLS work inherits the same pipeline.

## Objectives

- Structure a repository for automated FPGA builds (rtl/, constr/, scripts/, reports/, out/).
- Write a complete non-project-mode build.tcl with checkpoint/resume and report hooks.
- Drive it from a Makefile with pinned tool and parameterized targets.
- Implement a WNS/WHS/TNS timing gate that fails the build with exit code 1.
- Wire the flow into GitHub Actions on a self-hosted runner with artifact upload.
- Bake the git hash into the bitstream and verify it, for reproducibility.

## Prerequisites

- Vivado 2023.2 on PATH (WebPACK-class license suffices for this design).
- A GitHub account and a machine that can register a self-hosted runner (can be your workstation).
- Section 8 read: non-project mode, checkpoints, gates, runners, retention.

## Part 1: Repository Structure

```
fpga-ci-lab/
  rtl/top_led_chaser.sv      # DUT: counter + GIT_HASH register
  constr/zcu102_led.xdc      # LED pins + clock + DRC handling
  scripts/build.tcl          # non-project build, checkpoint/resume
  scripts/check_timing.tcl   # WNS/WHS/TNS gate (exit 1 on failure)
  Makefile
  .gitignore                 # out/ reports/ *.jou *.log .Xil/
  .github/workflows/fpga.yml
```

Why non-project mode, in one sentence per claim: there is no `.xpr` binary
state to drift between machines (everything is text), every design step is
an explicit scripted call you can read in a review, and stages emit
checkpoints that CI can resume or archive. The DUT:

```systemverilog
// rtl/top_led_chaser.sv
module top_led_chaser #(
  parameter [31:0] GIT_HASH = 32'h00000000
) (
  input  logic       clk,
  output logic [1:0] led
);
  (* DONT_TOUCH = "true" *) logic [31:0] build_info;  // provenance register
  logic [25:0] cnt = '0;

  initial begin
    build_info = GIT_HASH;
    cnt        = '0;
  end

  always_ff @(posedge clk) cnt <= cnt + 1'b1;
  assign led = cnt[24+:2];              // walking 2-bit pattern on the LEDs
endmodule
```

Constraints - LED pins are the two verified endpoints of the bank-44 LED
group (AG14 and AL12, LVCMOS33); extend to the full group from AMD's ZCU102
master XDC if you later want all eight:

```tcl
# constr/zcu102_led.xdc
set_property -dict {PACKAGE_PIN AG14 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN AL12 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
create_clock -period 8.000 -name sys_clk [get_ports clk]

# clk is deliberately left without a PACKAGE_PIN: CI verifies timing, not
# hardware. Downgrade the unconstrained-I/O DRC so batch bitstream writes
# stay green; Part 6 (optional) restores the pin from the master XDC.
set_property SEVERITY Warning [get_drc_checks UCIO-1]
```

## Part 2: The Build Script

```tcl
# scripts/build.tcl
# usage: vivado -mode batch -source scripts/build.tcl \
#          -tclargs <part> <top> <outdir> <git_hash> <stage>
if {$argc < 5} {
  puts "ERROR: expected: part top outdir git_hash stage"; exit 1
}
set part [lindex $argv 0];  set top    [lindex $argv 1]
set outdir [lindex $argv 2]; set git_hash [lindex $argv 3]
set stage [lindex $argv 4]

set tool [version -short]
if {![string match "2023.2*" $tool]} {
  puts "WARN: Vivado $tool != pinned baseline 2023.2"
}
file mkdir $outdir reports
puts "== build: $top part=$part git=$git_hash tool=$tool stage=$stage"

# --- synthesis -------------------------------------------------------------
read_verilog -sv [glob rtl/*.sv]
read_xdc [glob constr/*.xdc]
set_property generic "GIT_HASH=32'h$git_hash" [current_fileset]
synth_design -top $top -part $part
write_checkpoint -force $outdir/post_synth.dcp
report_utilization    -file reports/post_synth_util.rpt
report_timing_summary -file reports/post_synth_timing.rpt
puts "BUILD_INFO: git_hash=0x$git_hash tool=$tool"
if {$stage eq "synth"} { puts "== done: post_synth.dcp"; exit 0 }

# --- implementation (resumes from the synthesis checkpoint) ----------------
if {![file exists $outdir/post_synth.dcp]} {
  error "no $outdir/post_synth.dcp - run 'make synth' first"
}
open_checkpoint $outdir/post_synth.dcp
opt_design
place_design
write_checkpoint -force $outdir/placed.dcp
phys_opt_design
route_design
write_checkpoint -force $outdir/routed.dcp
report_timing_summary -file reports/timing_summary.rpt
report_utilization    -file reports/routed_util.rpt
report_power          -file reports/power.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
puts "== routed: WNS=$wns ns (policy gate: scripts/check_timing.tcl)"
write_bitstream -force -bin_file $outdir/$top
puts "== done: $outdir/$top.bit (+ .bin), checkpoints in $outdir/"
```

Note the shape Section 8 asked for: a checkpoint after every major stage
(post_synth, placed, routed), report hooks into reports/, and the git hash
flowing in as a generic so the netlist literally contains the commit.

## Part 3: The Makefile

```make
# Pin the toolchain: one variable, one place
VIVADO    ?= vivado
PART      := xczu9eg-ffvb1156-2-e
TOP       := top_led_chaser
GIT_HASH  ?= $(shell git rev-parse --short=8 HEAD 2>/dev/null || echo 0)

.PHONY: synth impl bit reports gate clean

synth:
	$(VIVADO) -mode batch -source scripts/build.tcl \
	  -tclargs $(PART) $(TOP) out $(GIT_HASH) synth

impl:
	$(VIVADO) -mode batch -source scripts/build.tcl \
	  -tclargs $(PART) $(TOP) out $(GIT_HASH) impl

bit:
	$(VIVADO) -mode batch -source scripts/build.tcl \
	  -tclargs $(PART) $(TOP) out $(GIT_HASH) bit

reports: bit

gate: bit
	$(VIVADO) -mode batch -source scripts/check_timing.tcl -tclargs out

clean:
	rm -rf out reports *.log *.jou .Xil
```

Log hygiene: Vivado drops `vivado*.log`/`.jou` and a `.Xil/` scratch dir in
the working directory - all ignored, never committed. `make clean && make
bit` is the clean-room build; get in the habit of trusting only that.

## Part 4: The Gate - and Proving It Bites

```tcl
# scripts/check_timing.tcl - WNS/WHS/TNS gate; exit 1 on any negative slack
set outdir [lindex $argv 0]
open_checkpoint $outdir/routed.dcp

set wns [get_property SLACK [get_timing_paths -delay_type max -max_paths 1 -nworst 1]]
set whs [get_property SLACK [get_timing_paths -delay_type min -max_paths 1 -nworst 1]]
set tns 0.0
foreach p [get_timing_paths -slack_lesser_than 0 -max_paths 1000] {
  set tns [expr {$tns + [get_property SLACK $p]}]
}
puts "GATE: WNS=$wns WHS=$whs TNS=$tns"
if {$wns < 0 || $whs < 0 || $tns < 0} {
  puts "GATE: FAIL - negative slack, merge blocked"; exit 1
}
puts "GATE: PASS"; exit 0
```

Now sabotage it: edit `constr/zcu102_led.xdc` and tighten the clock from
8.000 ns to 1.000 ns. Run `make gate` - the counter's carry chain cannot
close 1 GHz, the gate prints FAIL and exits 1, make aborts with Error 1.
This is the whole point of gating: the constraint bug is caught by the
machine, not by whoever happened to program the board. Restore 8.000 ns;
`make gate` goes green. (A missing false path on an async input produces the
same red CI by a subtler route - if you add a button input in the optional
exercise, leave its false_path out once and watch.)

## Part 5: CI on GitHub Actions

Self-hosted runner: on your Vivado machine, follow GitHub's Settings ->
Actions -> Runners -> New self-hosted runner instructions (download,
configure with a token, install as a service). The runner needs Vivado
2023.2 on PATH and network reach to GitHub; licenses float as usual.

```yaml
# .github/workflows/fpga.yml
name: fpga-ci
on:
  push:
    branches: [main]
  pull_request:

jobs:
  build:
    runs-on: self-hosted        # Vivado lives on the LAN; GitHub orchestrates
    steps:
      - uses: actions/checkout@v4
      - name: Report toolchain
        run: vivado -version
      - name: Clean-room build
        run: make clean && make bit
      - name: Timing gate (WNS/WHS/TNS)
        run: make gate
      - name: Archive reports and bitstreams
        uses: actions/upload-artifact@v4
        with:
          name: fpga-build-${{ github.sha }}
          path: |
            reports/
            out/*.bit
            out/*.bin
          retention-days: 14
          if-no-files-found: error
```

Push the repo, watch the run go green, and download the artifact: it must
contain timing_summary.rpt, the utilization and power reports, and both
bitstream formats. Then push the sabotage commit (period 1.000) on a branch
and open a PR: the PR check goes red at the gate step - a broken constraint
can never reach main again. Retention is set to 14 days: artifacts are
reproducible by definition, so paying storage forever is waste - Section 8's
retention argument.

## Part 6: Reproducibility Discipline

1. **Tool pin:** the Makefile's version check warns on any Vivado other than
2023.2; CI's `vivado -version` log line records what actually ran.
2. **Provenance in the netlist:** the build banner prints the hash, and the
`build_info` register holds it: open the routed checkpoint and spot-check
INIT values, e.g. `get_property INIT [get_cells build_info_reg[0]]` against
bits of `git rev-parse --short=8 HEAD`.
3. **Clean-clone test:** clone your own repo into /tmp, `make bit`, confirm
GATE: PASS - if it only builds on your machine, it does not build.
4. **Optional hardware step:** take the sys_clk PACKAGE_PIN and IOSTANDARD
lines from AMD's ZCU102 master XDC, program the board, and watch the 2-LED
walk; use an ILA or hw readback to confirm build_info.
5. **Optional exercise:** replace rtl/ with the Lab 2 HLS FIR plus a
wrapper, or the Lab 3 block design's exported netlist; the pipeline does not
care what the DUT is.

## Verification Checkpoints

| Checkpoint | Target | Method |
| --- | --- | --- |
| Clean-room build | `make clean && make bit` succeeds from fresh clone | local + CI log |
| Gate green | GATE: PASS, WNS/WHS >= 0, TNS = 0 | check_timing output |
| Gate red on sabotage | exit code 1, GATE: FAIL printed | Part 4 sabotage run |
| CI artifact | reports + .bit + .bin present after 14-day retention set | artifact download |
| Provenance | BUILD_INFO banner and build_info INIT match git rev-parse | log + checkpoint probe |

**Quantitative targets:** routed WNS and WHS recorded (positive, with the
counter path as the critical path); sabotage run's exit code 1 captured in
the transcript; artifact size and retention (14 days) confirmed; hash match
between `git rev-parse --short=8 HEAD`, the build banner, and at least one
INIT probe bit.

## Conceptual Questions

1. Name two concrete reproducibility hazards of project mode that this
repository's structure eliminates, and what replaces each as the source of
truth.
2. Your routed build fails timing after a two-hour implementation. Which
checkpoint do you resume from, what do you re-run, and what does that save?
3. The gate fails on WNS alone in one design and on TNS in another with a
healthy WNS. What is the difference between these two failure shapes, and
which is more dangerous to waive?
4. Why does this flow use a self-hosted runner rather than GitHub-hosted
images, and what does that choice cost in maintenance? Where does the
checkpoint-not-binary principle soften that cost?

---

**Presented by: Hossam Hassan, PhD**
