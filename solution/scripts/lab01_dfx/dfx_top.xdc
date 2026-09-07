# Lab01 DFX top constraints (ZCU102): 200 MHz FCLK0 from PS in the real BD;
# standalone clk port for offline runs. LED pins per the lab Part 2.
create_clock -period 5.000 -name clk [get_ports clk]
# On the board, clk comes from PS pl_clk0: use the FCLK pin pair instead and
# delete the clk port. For offline flow bring-up, drive clk from JTAG-clocked
# BBG or run to route-only (write_bitstream needs real pins: see lab XDC).
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports decouple]
# LED pins (ZCU102, from Lab01 Part 2):
set_property -dict {PACKAGE_PIN AG14 IOSTANDARD LVCMOS15} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN AF13 IOSTANDARD LVCMOS15} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN AE13 IOSTANDARD LVCMOS15} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN AJ14 IOSTANDARD LVCMOS15} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN AJ15 IOSTANDARD LVCMOS15} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN AH13 IOSTANDARD LVCMOS15} [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN AH14 IOSTANDARD LVCMOS15} [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN AL12 IOSTANDARD LVCMOS15} [get_ports {led[7]}]
