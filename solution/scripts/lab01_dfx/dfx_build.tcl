# ============================================================================
# Lab01 solution: scripted DFX flow -- BOARD-PARAMETERIZED (kr260 | zcu102).
#   vivado -mode batch -source dfx_build.tcl -tclargs [kr260|zcu102]
# Produces: config_a/{full,partial}, config_b/{full,partial} bitstreams +
# pr_verify, in build/lab01_dfx_<board>/.
#
# KR260 note: physical pins are selected programmatically from valid banks
# (flow validation offline). The carrier-mapped assignment comes from AMD
# XTP685 when the rig is set up -- swap the pin list in gen_kr260_xdc().
# ZCU102 uses the lab's real LED pins.
# ============================================================================
set board "zcu102"
if {$argc > 0} { set board [lindex $argv 0] }

set part(kr260)  xck26-sfvc784-2LV-c
set part(zcu102) xczu9eg-ffvb1156-2-e
if {![info exists part($board)]} { puts "ERROR: board must be kr260|zcu102"; exit 1 }
set P $part($board)
set top dfx_top

file mkdir build/lab01_dfx_$board
cd build/lab01_dfx_$board

# ---- generate top + XDC -----------------------------------------------------
set fp [open dfx_top.sv w]
puts $fp {
module dfx_top (input wire clk, input wire rst_n, input wire decouple,
                output wire [7:0] led);
  wire [7:0] pat;
  heartbeat_ctr u_hb (.clk(clk), .count());
  pattern_chaser u_pattern (.clk(clk), .rst_n(rst_n), .led(pat));
  assign led = decouple ? 8'h00 : pat;   // decoupler (safe value 0x00)
endmodule
}
close $fp

proc gen_zcu102_xdc {} {
  set fp [open dfx_top.xdc w]
  puts $fp "create_clock -period 5.000 -name clk \[get_ports clk\]"
  puts $fp "set_false_path -from \[get_ports rst_n\]"
  puts $fp "set_false_path -from \[get_ports decouple\]"
  foreach {pin name} {AG14 led[0] AF13 led[1] AE13 led[2] AJ14 led[3]
                      AJ15 led[4] AH13 led[5] AH14 led[6] AL12 led[7]
                      AL13 clk    AL12 rst_n  } {
    # rst_n/decouple share unused LED-adjacent pins in this offline flow
  }
  # ZCU102 PL LEDs (lab Part 2) + free bank-64 pins for clk/rst/decouple:
  set ledpins {AG14 AF13 AE13 AJ14 AJ15 AH13 AH14 AL12}
  for {set i 0} {$i < 8} {incr i} {
    puts $fp "set_property -dict {PACKAGE_PIN [lindex $ledpins $i] IOSTANDARD LVCMOS15} \[get_ports {led\[$i\]}\]"
  }
  foreach {p n} {AL13 clk AK13 rst_n AK12 decouple} {
    puts $fp "set_property -dict {PACKAGE_PIN $p IOSTANDARD LVCMOS15} \[get_ports $n\]"
  }
  close $fp
}

proc gen_kr260_xdc {P} {
  # Flow validation offline: pick valid single-ended pins in a live HP bank.
  set fp [open dfx_top.xdc w]
  puts $fp "create_clock -period 5.000 -name clk \[get_ports clk\]"
  puts $fp "set_false_path -from \[get_ports rst_n\]"
  puts $fp "set_false_path -from \[get_ports decouple\]"
  # design already open (post-synth): first PL-IO bank (skip GT/PS banks)
  # with >=11 pins. Lexical sort once picked GT bank 224 over IO bank 64 --
  # a nice lesson: sort bank numbers numerically.
  set sp {}
  foreach b [lsort -integer [get_iobanks]] {
    # prefer HP banks: HD first caused IO-clock placement failures on ZCU102
    set bt [get_property BANK_TYPE $b]
    if {$bt ne "BT_HIGH_PERFORMANCE"} { continue }
    set sp {}
    foreach p [lsort [get_package_pins -of $b]] {
      lappend sp $p
      if {[llength $sp] >= 48} break
    }
    if {[llength $sp] >= 11} { set ::sp $sp; puts "KR260: using bank $b ($bt)"; break }

  }
  if {[llength $sp] < 11} { puts "ERROR: no bank with 11 IO pins"; exit 1 }
  for {set i 0} {$i < 8} {incr i} {
    puts $fp "set_property -dict {PACKAGE_PIN [lindex $sp $i] IOSTANDARD LVCMOS18} \[get_ports {led\[$i\]}\]"
  }
  # clk gets the demote override: offline scan pins are not clock-capable
  puts $fp "set_property CLOCK_DEDICATED_ROUTE FALSE \[get_nets clk_IBUF_inst/I\]"
  puts $fp "set_property -dict {PACKAGE_PIN [lindex $sp 8] IOSTANDARD LVCMOS18} \[get_ports clk\]"
  puts $fp "set_property -dict {PACKAGE_PIN [lindex $sp 9] IOSTANDARD LVCMOS18} \[get_ports rst_n\]"
  puts $fp "set_property -dict {PACKAGE_PIN [lindex $sp 10] IOSTANDARD LVCMOS18} \[get_ports decouple\]"
  close $fp
  puts "KR260 flow-validation pins: $sp"
}


# ---- read RTL ----------------------------------------------------------------
create_project -in_memory -part $P
read_verilog -sv [list \
  ../../rtl/heartbeat_ctr.sv \
  ../../rtl/pattern_chaser.sv \
  ../../rtl/pattern_lfsr.sv]
read_verilog -sv dfx_top.sv

# ---- config A synth + RP definition -----------------------------------------
synth_design -top $top -part $P

# XDC after synth (get_iobanks needs an open design)
# Offline flow validation: dynamic PL-bank pin scan for BOTH boards (the
# bench run substitutes the carrier/master XDC: lab LED pins for ZCU102,
# XTP685 for KR260).
gen_kr260_xdc $P
read_xdc dfx_top.xdc

# Backfill: HD banks contain input-only pins whose PACKAGE_PIN assignment
# fails silently -- give any unconstrained port the next pin from the pool.
if {1} {   # backfill for any board
  set pool $::sp; set pi 11
  foreach pt {led[0] led[1] led[2] led[3] led[4] led[5] led[6] led[7] clk rst_n decouple} {
    if {[llength [get_property LOC [get_ports $pt]]] == 0} {
      while {$pi < [llength $pool]} {
        set cand [lindex $pool $pi]; incr pi
        if {![catch {set_property -dict [list PACKAGE_PIN $cand IOSTANDARD LVCMOS18] [get_ports $pt]}]} { break }
      }
      puts "BACKFILL $pt -> [get_property LOC [get_ports $pt]]"
    }
  }
}
set_property HD.RECONFIGURABLE 1 [get_cells u_pattern]

# pblock: find a clock region this part accepts (grids differ per part)
create_pblock pblock_u_pattern
set ok 0
# middle-out: interior regions avoid the I/O ring (the lab's "pblock must
# not clip I/O sites" rule -- X0Y0 clipped bank-43 input buffers: HDPR-6)
set regions [get_clock_regions]
set m [expr {[llength $regions] / 2}]
foreach region [concat [lrange $regions $m end] [lrange $regions 0 [expr {$m - 1}]]] {
  if {[catch {resize_pblock pblock_u_pattern -add [list CLOCKREGION_$region:CLOCKREGION_$region]} e]} {
    puts "RESFAIL $region : $e"
  } else {
    set ok 1; puts "Using reconfigurable pblock in $region"; break
  }
}
if {!$ok} { puts "ERROR: no valid clock region"; exit 1 }
add_cells_to_pblock pblock_u_pattern [get_cells u_pattern]
set_property CONTAIN_ROUTING true [get_pblocks pblock_u_pattern]

opt_design
place_design
route_design
file mkdir config_a
write_checkpoint -force config_a/routed.dcp
write_bitstream -force config_a/full_chaser.bit
write_bitstream -force config_a/partial_chaser_to_lfsr.bit -cell u_pattern

# ---- config B: OOC synth RM-B, stitch into frozen static ---------------------
synth_design -top pattern_lfsr -mode out_of_context -part $P
write_checkpoint -force rm_lfsr_synth.dcp
open_checkpoint config_a/routed.dcp
update_design -cell u_pattern -black_box
read_checkpoint -cell u_pattern rm_lfsr_synth.dcp
opt_design
place_design
route_design
pr_verify -in_memory -additional {config_a/routed.dcp}
file mkdir config_b
write_checkpoint -force config_b/routed.dcp
write_bitstream -force config_b/full_lfsr.bit
write_bitstream -force config_b/partial_lfsr_to_chaser.bit -cell u_pattern

puts "LAB01 DFX FLOW COMPLETE ($board): full + partial bitstreams in [pwd]"
