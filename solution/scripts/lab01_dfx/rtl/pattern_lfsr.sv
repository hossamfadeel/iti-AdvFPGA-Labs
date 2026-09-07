`timescale 1ns / 1ps
// Lab01 RM-B: LFSR pseudo-random pattern (same interface as RM-A)
(* KEEP_HIERARCHY = "yes" *)   // DFX: RM boundary must survive synthesis
module pattern_lfsr (
  input  logic       clk,
  input  logic       rst_n,
  output logic [7:0] led
);
  logic [27:0] div = '0;
  logic [7:0]  lfsr = 8'hAC;
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      div <= '0;  lfsr <= 8'hAC;
    end else begin
      div <= div + 1'b1;
      if (div[21]) begin
        div  <= '0;
        lfsr <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        led  <= lfsr;
      end
    end
endmodule
