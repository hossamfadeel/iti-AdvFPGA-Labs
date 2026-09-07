// Lab01 behavioral TB: decouple boundary, RM reset sequencing, static
// heartbeat continuity across the swap window (from the lab, self-checking)
`timescale 1ns / 1ps
module tb_dfx_behavior;
  logic        clk = 0;
  logic        rm_rst_n = 0;
  logic        decouple = 0;
  logic [7:0]  rm_led;
  logic [7:0]  decoupled_led;
  logic [31:0] hb_count;

  always #5 clk = ~clk;

  heartbeat_ctr u_hb (.clk(clk), .count(hb_count));
  pattern_chaser u_rm_a (.clk(clk), .rst_n(rm_rst_n), .led(rm_led));
  assign decoupled_led = decouple ? 8'h00 : rm_led;

  int errs = 0;
  initial begin
    $display("[TB] Starting DFX Behavioral Verification...");
    decouple = 1; rm_rst_n = 0; #100;
    if (decoupled_led !== 8'h00) begin
      $error("[TB ERROR] LEDs not zero in decouple state!"); errs++;
    end
    rm_rst_n = 1; #20; decouple = 0;
    $display("[TB] Decouple released. Initial RM-A: %b", decoupled_led);
    #1000;
    if (!(hb_count > 32'd100)) begin
      $error("[TB ERROR] Heartbeat counter stalled!"); errs++;
    end
    $display("[TB] Initiating Reconfiguration Sequence...");
    decouple = 1; rm_rst_n = 0; #500;
    if (decoupled_led !== 8'h00) begin
      $error("[TB ERROR] Glitch on LED boundary!"); errs++;
    end
    // NOTE: the lab's original threshold (>200) is unreachable in the lab's
    // own 1620 ns timeline (~162 cycles max at 100 MHz); fixed to 150.
    if (!(hb_count > 32'd150)) begin
      $error("[TB ERROR] Heartbeat stalled during reconfig window!"); errs++;
    end
    rm_rst_n = 1; decouple = 0;
    $display("[TB] Reconfig complete. LED: %b, HB: %d", decoupled_led, hb_count);
    if (errs == 0) begin
      $display("PASS: tb_dfx_behavior (decouple safe-value, RM reset, heartbeat continuity)");
      $finish;
    end else begin
      $display("FAIL: tb_dfx_behavior (%0d errors)", errs);
      $finish;
    end
  end
endmodule
