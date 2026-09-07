`timescale 1ns / 1ps
// Lab05: BERT-style checker (from the lab, verbatim)
module lab_checker #(
  parameter int PAYLOAD_W = 64
) (
  input  logic                     user_clk,
  input  logic                     rst_n,
  input  logic                     channel_up,
  input  logic [PAYLOAD_W-1:0]     tdata,
  input  logic [(PAYLOAD_W/8)-1:0] tkeep,
  input  logic                     tvalid,
  input  logic                     tlast,
  output logic [47:0]              word_count,
  output logic [47:0]              error_count
);
  logic        locked;
  logic [31:0] seq, lfsr, exp_seq, exp_lfsr;
  logic [PAYLOAD_W-1:0] expected;
  function automatic logic [31:0] lfsr_next(input logic [31:0] s);
    lfsr_next = {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction
  assign exp_seq  = seq + 32'd1;
  assign exp_lfsr = lfsr_next(lfsr);
  assign expected = {exp_seq, exp_lfsr};
  always_ff @(posedge user_clk) begin
    if (!rst_n || !channel_up) begin
      locked <= 1'b0;  word_count <= '0;  error_count <= '0;
      seq <= '0;  lfsr <= '0;
    end else if (tvalid) begin
      word_count <= word_count + 48'd1;
      if (!locked) begin
        locked <= 1'b1;  seq <= tdata[63:32];  lfsr <= tdata[31:0];
      end else if (tdata !== expected || tkeep !== '1) begin
        error_count <= error_count + 48'd1;
        seq <= tdata[63:32];  lfsr <= tdata[31:0];
      end else begin
        seq <= exp_seq;  lfsr <= exp_lfsr;
      end
    end
  end
endmodule
