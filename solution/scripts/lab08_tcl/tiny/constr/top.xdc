create_clock -period 10.000 -name clk [get_ports clk]
set_false_path -from [get_ports rst_n]
