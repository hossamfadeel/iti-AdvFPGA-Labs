# Lab02 solution driver. Variant via env FIR_SOL (v0|v1|v2|v3), default v0.
# csim always; csynth always; cosim when FIR_COSIM=1; IP export for v3.
set SOL v0
if {[info exists ::env(FIR_SOL)]} { set SOL $::env(FIR_SOL) }
open_project -reset fir_proj_$SOL
set_top fir_top
add_files variants/fir_$SOL.cpp -cflags "-I."
add_files -tb fir_tb.cpp -cflags "-I."
open_solution $SOL -flow_target vivado
set_part xczu9eg-ffvb1156-2-e
create_clock -period 6.667
csim_design
csynth_design
if {[info exists ::env(FIR_COSIM)] && $::env(FIR_COSIM) eq "1"} {
    cosim_design -trace_level none
}
if {$SOL eq "v3"} { export_design -format ip_catalog -rtl verilog }
exit
