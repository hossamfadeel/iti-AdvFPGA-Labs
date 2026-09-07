// Lab08 tiny design: exercises the scripted flow end to end
module blink #(parameter logic [25:0] MAX = 26'd50_000_000) (
  input  wire clk,
  input  wire rst_n,
  output wire led
);
  logic [25:0] cnt = '0;
  logic        tog = 1'b0;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      cnt <= '0;  tog <= 1'b0;
    end else if (cnt == MAX) begin
      cnt <= '0;  tog <= ~tog;
    end else begin
      cnt <= cnt + 1'b1;
    end
  end
  assign led = tog;
endmodule
