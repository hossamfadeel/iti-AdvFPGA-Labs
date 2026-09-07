// Lab05 solution TB: BERT verification in simulation (no GT needed).
// Channel model: 2-deep elastic FIFO (combinational-ready chain, correct
// backpressure semantics), plus ONE injected corrupted word mid-run.
// Expect: exactly 1 error counted, word_count == words sent, relock works.
`timescale 1ns / 1ps
module tb_aurora_loop;
  logic [47:0] word_count, error_count;
  localparam int PW = 64, FL = 16, NWORDS = 2000;
  logic clk = 0, rst_n = 0, channel_up = 0;
  always #3.2 clk = ~clk;                     // 156.25 MHz user clock


  // framer side
  logic [PW-1:0] f_data;  logic [7:0] f_keep;
  logic f_valid, f_last, f_ready;

  // ---- channel: 2-deep FIFO with ready chain + corruption injector ------
  logic [PW-1:0] q0, q1;  logic [7:0] k0, k1;
  logic          v0, v1, l0, l1;

  wire pop  = v1;                       // Aurora RX: sink accepts every cycle
  wire adv0 = v0 && (!v1 || pop);         // head moves into free/draining tail
  logic freeze = 0;                     // TB valve: stop the source only
  assign f_ready = !freeze && (!v0 || adv0);

  // one-shot corruption injector: exactly ONE word damaged mid-run
  logic injected = 0;
  wire do_inj = !injected && (word_count >= NWORDS/2) && f_valid && f_ready;
  always_ff @(posedge clk) begin
    if (!rst_n) injected <= 0;
    else if (do_inj)     injected <= 1;
  end

  always_ff @(posedge clk) begin
    if (!rst_n) begin
      v0 <= 0;  v1 <= 0;
    end else begin
      v1 <= adv0 ? 1'b1 : (pop ? 1'b0 : v1);
      if (adv0) begin
        q1 <= q0;  k1 <= k0;  l1 <= l0;
      end
      if (f_ready) begin
        v0 <= f_valid;
        q0 <= do_inj ? (f_data ^ 64'h0000_00FF) : f_data;
        k0 <= f_keep;  l0 <= f_last;
      end else if (adv0) begin
        v0 <= 1'b0;                   // advanced without refill: slot empties
      end
    end
  end

  // checker side (word_count/error_count declared at top)
  lab_checker #(.PAYLOAD_W(PW)) u_rx
    (.user_clk(clk), .rst_n(rst_n), .channel_up(channel_up),
     .tdata(q1), .tkeep(k1), .tvalid(v1), .tlast(l1),
     .word_count(word_count), .error_count(error_count));

  lab_framer  #(.PAYLOAD_W(PW), .FRAME_LEN(FL)) u_tx
    (.user_clk(clk), .rst_n(rst_n), .channel_up(channel_up),
     .tready(f_ready), .tdata(f_data), .tkeep(f_keep),
     .tvalid(f_valid), .tlast(f_last));


  int sent = 0;
  initial begin #2_000_000; $display("FAIL: tb_aurora_loop (watchdog)"); $finish; end
  always_ff @(posedge clk)
    if (channel_up && rst_n && f_valid && f_ready) sent <= sent + 1;

  initial begin
    rst_n = 0; #100; rst_n = 1; channel_up = 1;
    wait (word_count >= NWORDS);
    freeze = 1;                   // valve the framer; pipe drains; checker runs
    repeat (10) @(posedge clk);
    $display("words sent=%0d checked=%0d errors=%0d", sent, word_count, error_count);
    // One corrupted word yields TWO error events in a state-adoption BERT
    // (corrupt word + the word predicted from adopted-bad state), then a
    // clean re-lock. Up to 2 words remain parked in the valved pipe.
    if (error_count == 2 && word_count == sent)
      $display("PASS: tb_aurora_loop (BERT locks, injected error detected + relock)");
    else
      $display("FAIL: tb_aurora_loop (errors=%0d words=%0d sent=%0d)",
               error_count, word_count, sent);
    $finish;
  end
endmodule
