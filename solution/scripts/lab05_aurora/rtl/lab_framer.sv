`timescale 1ns / 1ps
// Lab05: PRBS + sequence-counter framer (from the lab, verbatim)
module lab_framer #(
  parameter int PAYLOAD_W = 64,
  parameter int FRAME_LEN = 16
) (
  input  logic                     user_clk,
  input  logic                     rst_n,
  input  logic                     channel_up,
  input  logic                     tready,
  output logic [PAYLOAD_W-1:0]     tdata,
  output logic [(PAYLOAD_W/8)-1:0] tkeep,
  output logic                     tvalid,
  output logic                     tlast
);
  logic [31:0] seq, lfsr;
  logic [5:0]  wcnt;
  function automatic logic [31:0] lfsr_next(input logic [31:0] s);
    lfsr_next = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction
  assign tvalid = channel_up && rst_n;
  assign tkeep  = '1;
  assign tdata  = {seq, lfsr};
  assign tlast  = (wcnt == FRAME_LEN-1);
  always_ff @(posedge user_clk) begin
    if (!rst_n || !channel_up) begin
      seq <= 32'd0;  lfsr <= 32'hACE15555;  wcnt <= '0;
    end else if (tvalid && tready) begin
      seq  <= seq + 32'd1;
      lfsr <= lfsr_next(lfsr);
      wcnt <= (wcnt == FRAME_LEN-1) ? '0 : wcnt + 6'd1;
    end
  end
endmodule
