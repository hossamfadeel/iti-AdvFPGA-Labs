// Lab01: static-region heartbeat counter (runs at 100 MHz, never resets)
`timescale 1ns / 1ps
module heartbeat_ctr (
  input  wire         clk,
  output logic [31:0] count
);
  logic [31:0] cnt = 32'd0;    // power-up value (not a procedural driver)
  always_ff @(posedge clk) cnt <= cnt + 32'd1;
  assign count = cnt;
endmodule
