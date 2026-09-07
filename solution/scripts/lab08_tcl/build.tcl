# Lab08 solution: non-project scripted flow. Usage:
#   vivado -mode batch -source build.tcl -tclargs synth|impl
set step [lindex $argv 0]
if {$step eq ""} { set step "synth" }
set part xczu9eg-ffvb1156-2-e
set top  blink

if {$step eq "synth"} {
    read_verilog -sv tiny/rtl/blink.sv
    read_xdc tiny/constr/top.xdc
    synth_design -top $top -part $part
    write_checkpoint -force build/synth.dcp
    report_utilization -file build/util_synth.rpt
    report_timing_summary -file build/timing_synth.rpt
    puts "SYNTH DONE"
}
if {$step eq "impl"} {
    open_checkpoint build/synth.dcp
    opt_design; place_design; phys_opt_design; route_design
    write_checkpoint -force build/impl.dcp
    report_timing_summary -file build/timing_impl.rpt
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1]]
    puts "WNS: $wns"
    if {$wns < 0} { puts "FAIL: WNS $wns"; exit 1 }
    puts "PASS: WNS $wns"
    write_bitstream -force build/blink.bit
}
