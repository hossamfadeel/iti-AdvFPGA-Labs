# Lab 05 -- Aurora 64B/66B SFP Loopback: Step-by-Step Solution

**BERT logic TESTED on this workstation (2025.2): PASS.**
GT/bring-up parts are board work; the soak-test logic is verified in sim.

## What was actually run (and passed)
`scripts/lab05_aurora/run_sim.sh` -> `PASS: tb_aurora_loop`
2002 words through framer -> elastic channel -> checker with ONE injected
corrupted word: exactly 2 error events, word counts match, relock clean.

## Step-by-step

### Parts 1-4 (board): cages, TX_DISABLE, two cores on bank 230, ILA
Follow the lab checklist; the constraints and IP parameters (156.25 MHz
refclk, x1 lane, 64-bit user width) are in the lab text; bring-up order
is lane_up -> channel_up, verified in the ILA capture.

### Part 5: the soak logic (verified in simulation)
1. `rtl/lab_framer.sv` + `rtl/lab_checker.sv` (from the lab, verbatim).
2. `tb/tb_aurora_loop.sv` adds: a 2-deep elastic channel with a CORRECT
   ready chain (a naive version had a combinational f_ready<->adv0 loop --
   see the pitfalls below), a one-shot corruption injector, and a source
   valve for clean drain.
3. **Key BERT semantics the test teaches:** one corrupted word produces
   TWO error events in a state-adoption checker (the corrupt word, plus
   the next word predicted from the adopted bad state), then a clean
   relock. If you measure "1 error per glitch" you are not adopting
   received state; if you measure an error flood, your sink is
   multi-counting held words (Aurora RX has NO tready -- each valid word
   appears exactly one cycle).
4. On the board: 5-minute soak, snapshot counters via ILA, throughput =
   delta_words * 64 / seconds; ceiling = 156.25 MHz * 64 = 10.0 Gbps;
   explain the gap (framing overhead + tvalid bubbles).

### Pitfalls found while testing (real, documented)
- Combinational ready loops in hand-rolled elastic buffers (v0=1,v1=0
  case: f_ready depends on adv0 depends on f_ready).
- Head slot must CLEAR when it advances without refill, or it recirculates
  a stale word forever.
- Checkers reset on `channel_up=0`: "freeze the link" also erases the
  evidence -- valve the producer instead.

### Part 6 (board): PCIe guided reading
lspci/lspci -vv on PetaLinux ZCU102: PS-GTR root port 00:00.0, empty tree
(no endpoints) -- the host side of Section 5's story.
