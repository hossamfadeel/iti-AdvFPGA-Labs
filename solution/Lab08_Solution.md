# Lab 8 Solution — Scripted Flows: TCL Builds and CI/CD
**Companion to Section 8: Scripted Flows: TCL + CI/CD**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Reference Approach

Non-project build.tcl (synth -> post_synth.dcp -> place -> placed.dcp ->
phys_opt -> route -> routed.dcp -> reports -> bitstream with -bin_file),
driven by a Makefile pinning part/top/hash/stage; separate policy gate in
check_timing.tcl; self-hosted Actions runner uploads reports and bitstreams
with 14-day retention.

## Clean-Room Build Milestones (console, abridged)

```
$ make clean && make bit
vivado -mode batch -source scripts/build.tcl -tclargs xczu9eg-ffvb1156-2-e \
       top_led_chaser out 1a2b3c4d bit
== build: top_led_chaser part=xczu9eg-ffvb1156-2-e git=1a2b3c4d tool=2023.2 stage=bit
BUILD_INFO: git_hash=0x1a2b3c4d tool=2023.2
== done: post_synth.dcp            (synth exit skipped; stage=bit)
== routed: WNS=6.4 ns ns (policy gate: scripts/check_timing.tcl)
== done: out/top_led_chaser.bit (+ .bin), checkpoints in out/
GATE: WNS=6.4 WHS=0.9 TNS=0.0
GATE: PASS
```

## Sabotaged (Red) Run

```
$ make gate   (after create_clock -period 1.000)
GATE: WNS=-2.9 WHS=0.7 TNS=-41.6
GATE: FAIL - negative slack, merge blocked
make: *** [Makefile:23: gate] Error 1
```

The negative WNS is the 26-bit counter carry chain asked to close 1 GHz;
TNS accumulates across the failing endpoint swarm. CI shows the same exit
code at the gate step of the PR check.

## CI and Artifacts

Green run artifacts: `fpga-build-<sha>.zip` containing reports/
(post_synth_util, post_synth_timing, timing_summary, routed_util, power),
out/top_led_chaser.bit and .bin. Retention 14 days as configured;
if-no-files-found: error makes a silently-empty artifact a failure, not a
surprise.

## Provenance Verification

```
$ git rev-parse --short=8 HEAD
1a2b3c4d
$ grep BUILD_INFO vivado.log
BUILD_INFO: git_hash=0x1a2b3c4d tool=2023.2
$ vivado -mode batch -nostderr <<'EOF'
open_checkpoint out/routed.dcp
get_property INIT [get_cells build_info_reg[0]]
EOF
1        ;# matches bit 0 of 0x1a2b3c4d (odd hash -> LSB 1)
```

## Common Failure Modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| UCIO-1 error at write_bitstream | clk left unconstrained deliberately, DRC active | keep the SEVERITY downgrade; or add the clock pin for hardware |
| make gate: no routed.dcp | only synth ran | run make bit first (Makefile dependency does this) |
| Runner offline / job queued forever | runner service down or token expired | re-register; check systemctl status of the runner service |
| WNS positive but WHS negative | rare on this design; usually async input without proper constraint | add false_path/set_max_delay on the CDC, never waive hold |

## Conceptual Question Answers

1. Hazards: .xpr binary state (replaced by read_* commands over tracked
sources) and implicit run settings remembered by the GUI (replaced by
explicit synth_design/opt/place/route options in the diffable script).
2. Resume from routed.dcp only if the fix is constraint-level (rerun
reporting/gate); a logic fix means back to post_synth.dcp (skip synthesis,
rerun implementation); either way synthesis' wall time is saved - and the
placed.dcp lets you inspect the failing placement before rerunning.
3. WNS failure: one critical path misses (fix locally - pipeline, loose
constraint); TNS with healthy WNS: many endpoints marginally negative - a
systemic constraint or clocking problem. The swarm is more dangerous to
waive because no single path documents the risk.
4. Vivado install and license live on lab LAN hardware, not in a public
image (tens of GB + license terms); cost: you maintain the runner box.
Checkpoints (and scripts) in the repo mean any machine with the pinned tool
can reproduce or resume the build - the runner is a convenience, not the
custodian of the flow.

## Grading Notes

Full credit requires: clean-clone build passing locally, sabotage transcript
with exit code 1, a green CI run with downloaded artifact listing, and the
three-way hash match (git, banner, INIT probe) recorded.

---

**Presented by: Hossam Hassan, PhD**
