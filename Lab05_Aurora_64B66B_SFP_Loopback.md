# Lab 5 — Aurora 64B/66B: 10G Link Between SFP+ Cages
**Companion to Section 5: PCIe + GT Transceivers**
**Board:** ZCU102 Evaluation Board (XCZU9EG-FFVB1156E) | **Level:** Advanced

---

## Introduction

Section 5 taught SerDes fundamentals: differential pairs with an embedded clock recovered by CDR, the encoding tax that separates GT/s from GB/s, and the UltraScale+ transceiver menu (GTH, GTY, GTM, PS-GTR). On the ZCU102 the PCIe story must be stated explicitly up front: the board's PCIe is a **PS-GTR Gen2 x4 root port** wired to slot P1. The board is the *host* - there is no edge connector, so there is no card-side PCIe hard-IP lab on this bench, and PCIe enumeration is left as a short guided-reading exercise in Part 6.

The hands-on GT work on this board is **Aurora 64B/66B over the SFP+ cages**. You will build two Aurora cores (PG074), LOC them to the GT channels behind two SFP+ cages, connect them with a passive DAC twinax cable, and watch the link come up: lane first, channel second. Unlike the 8B/10B links on the deck's encoding-tax slide, 64B/66B is *comma-less* - no comma symbols; every 66-bit block carries a 2-bit sync header, and the payload efficiency is 64/66 = 96.97%. You will verify that number against silicon. This lab is standalone but assumes you have read Section 5; it does not re-teach GT theory.

## Objectives

- Prepare the board: SFP+ cage numbering, TX_DISABLE jumpers, DAC install
- Generate and constrain two Aurora 64B/66B cores on GTH bank 230 at 10.3125 Gbps
- Bring the link up and read the lane_up/channel_up order correctly
- Run a framed PRBS soak test with a hardware error counter, then measure effective payload throughput against the 64B/66B ceiling
- Walk an lspci-based PCIe exploration under PetaLinux (guided reading)

## Prerequisites

- ZCU102 Evaluation Board (xczu9eg-ffvb1156-2-e) with PSU and USB cables
- **One passive SFP+ DAC twinax cable, 1-3 m** - any generic 10G passive DAC works (for example a 10Gtek 10GSFP+Cu-1M or FS 10G DAC-1M, about USD 15). Do not buy an active AOC or a 40G breakout.
- **Two jumper shunts** for the SFP TX_DISABLE headers (Part 1 - the #1 bring-up failure)
- Vivado 2023.2; JTAG via onboard J2; UART via micro-USB J83 channel 0 at 115200 8N1; Section 5 of the deck read (Labs 1-4 helpful but not required)

## Part 1: Board Preparation - Cages, TX_DISABLE Jumpers, and the DAC

The XCZU9EG has 24 GTH transceivers in 6 quads (banks 128, 129, 130, 228, 229, 230). The four SFP+ cages SFP0-SFP3 are wired to **GTH bank 230, channels X1Y12-X1Y15**. This lab uses SFP0 (X1Y12) and SFP1 (X1Y13).

1. With power OFF, find the SFP+ cages on the board edge and confirm the SFP0/SFP1 silkscreen numbering in your lab notebook.
2. Locate the **TX_DISABLE jumper headers** for the cages. They **ship OPEN, which means the transmitter is disabled**. A link with either end TX-disabled never reaches lane_up - the single most common ZCU102 Aurora bring-up failure. Install a shunt on the TX_DISABLE headers for SFP0 and SFP1.
3. Connect the DAC cable between SFP0 and SFP1 until it clicks; tug-test both ends. Cable direction is irrelevant - each end carries symmetric TX/RX pairs. Leave power off until Part 4.

## Part 2: Vivado Design - Two Aurora 64B/66B Cores on Bank 230

Create a project for board part `xczu9eg-ffvb1156-2-e`, then add the **Aurora 64B/66B** core (PG074) twice, named `aurora_core0` (SFP0) and `aurora_core1` (SFP1). Customize both identically:

| Parameter | Value |
| --- | --- |
| Line rate | 10.3125 Gbps |
| Number of lanes | 1 |
| Interface | Streaming (framed) |
| Endianness | Little |
| GT refclk frequency | 156.25 MHz |
| Init clock frequency | 125 MHz |
| Scrambler/Descrambler | Enabled (both) |

Clocking and reset wiring, per core:

- **gt_refclk1** comes from **USER_MGT_SI570_CLOCK2**, the programmable Si570 oscillator with a 156.25 MHz default, on pins C8/C7 - the QPLL reference for bank 230. Both cores share the quad's QPLLs; no conflict, since both run the same line rate (Section 5's QPLL-scarcity slide is why you check this first).
- **init_clk** comes from the **fixed 125 MHz CLK_125** oscillator on pins G21/F21 (bank 47). This is the standard robust choice: free-running, never stops, never reprogrammed (see the Si570 gotcha in Part 4).
- **Reset domains:** assert the core system `reset` (init_clk domain) until power is good after configuration, then release. The core sequences its own GT resets through `sys_reset_out` - do not manually pulse GT resets around it. Keep user logic entirely in the user clock domain; cross nothing into init_clk.

For the first bring-up, use the core's **example frame generator/checker**: right-click the core, Open IP Example Design, and study how frame_gen/frame_check, the GT wrapper, and the support/reset logic connect. In your lab top, instantiate both cores, each with its example frame generator on TX and frame checker on RX. Physical dataflow: core0 TX -> SFP0 -> DAC -> SFP1 -> core1 RX, and symmetrically core1 TX -> SFP0 RX for the return direction.

## Part 3: ILA, LEDs, and Constraints

**LEDs (immediate visibility):** drive four LEDs from bank 44 (LVCMOS33); GPIO_LED[7:0] map to AG14, AF13, AE13, AJ14, AJ15, AH13, AH14, AL12. Assign LED0 = core0 lane_up, LED1 = core0 channel_up, LED2 = core1 lane_up, LED3 = core1 channel_up.

**ILA:** add one ILA, depth 1024, probe clock = core0 user clock. Probe lane_up and channel_up for both cores, s_axi_tx_tvalid/tready, and (after Part 5) word_count and error_count. Trigger setup:

1. Open Hardware Manager, connect to J2, program the device, then set the lane_up_c0 probe compare value to **R** (rising edge)
2. Arm; the capture stops a few hundred cycles after the rising edge
3. For the soak, retrigger on `error_count != 0` - it should never fire

**XDC pattern** - the board master XDC (`zcu102-master-xdc`) supplies the pin LOCs; uncomment or copy these, and adapt hierarchical names to your synthesized netlist:

```tcl
# Reference clock: USER_MGT_SI570_CLOCK2 (Si570, 156.25 MHz default), pins C8/C7
set_property PACKAGE_PIN C8 [get_ports gt_refclk1_p]
set_property PACKAGE_PIN C7 [get_ports gt_refclk1_n]
create_clock -period 6.400 -name gt_refclk1 [get_ports gt_refclk1_p]

# Init clock: CLK_125 fixed 125 MHz, pins G21/F21 (bank 47)
set_property PACKAGE_PIN G21 [get_ports clk_125_p]
set_property PACKAGE_PIN F21 [get_ports clk_125_n]
create_clock -period 8.000 -name clk_125 [get_ports clk_125_p]

# GT channel LOCs: SFP0 -> X1Y12, SFP1 -> X1Y13 (GTH bank 230)
set_property LOC GTHE4_CHANNEL_X1Y12 [get_cells -hier -filter {NAME =~ *core0*gth_channel*}]
set_property LOC GTHE4_CHANNEL_X1Y13 [get_cells -hier -filter {NAME =~ *core1*gth_channel*}]

# Clock-domain separation: init_clk vs the refclk-derived user domains
set_clock_groups -asynchronous \
  -group [get_clocks clk_125] \
  -group [get_clocks -include_generated_clocks user_clk_c0] \
  -group [get_clocks -include_generated_clocks user_clk_c1]
```

The clock-group statement matters: the init_clk domain and the refclk-derived user domains are unrelated, and timing analysis must not try to close paths between them. Check the clock utilization report for the exact generated-clock names on your build.

## Part 4: Bring-Up - lane_up, then channel_up

Power on and program via JTAG J2. **Order matters:** `lane_up` asserts first - the GT achieved CDR lock and 64B/66B block sync (comma-less, so sync means valid 2-bit headers on 66-bit boundaries). Then `channel_up` asserts - Aurora protocol initialization completed and the channel validated. Record elapsed time from PROGRAM to each event. If the link does not come up within ~10 seconds, walk this tree (the solution file has the full decision table):

1. **TX_DISABLE jumpers** - open headers mean the transmitter is off. Check both cages.
2. **Refclk frequency** - the Si570 must sit at its 156.25 MHz default. One-line gotcha to know before moving to Linux: under Linux the Si570 can be reprogrammed to 148.5 MHz for HDMI unless protected in the device tree. This lab runs from JTAG/bare-metal so it does not apply - but if you ever boot Linux first, power-cycle before this lab.
3. **Wrong X1Y placement or DAC seating** - XAPP1305 contains a known transceiver-location erratum: it says X0Y4, but the SFP+ quad is really X1Y12-X1Y15 in bank 230. Trust the LOC, not the app note. Then reseat both DAC ends and inspect the contacts.

## Part 5: Soak Test - PRBS Framer, Error Counter, Throughput

Replace each core's example frame generator with the framer below and each frame checker with the checker (one framer/checker pair per direction). Both run entirely in the user clock domain; drive `rst_n` from VIO so you can clear counters without reprogramming.

```systemverilog
// lab_framer.sv - PRBS + sequence counter, FRAME_LEN-word framed stream
module lab_framer #(
  parameter int PAYLOAD_W = 64,             // matches Aurora user width
  parameter int FRAME_LEN = 16              // words per frame
) (
  input  logic                     user_clk,
  input  logic                     rst_n,   // synchronous, user_clk domain
  input  logic                     channel_up,
  input  logic                     tready,  // s_axi_tx_tready
  output logic [PAYLOAD_W-1:0]     tdata,   // s_axi_tx_tdata
  output logic [(PAYLOAD_W/8)-1:0] tkeep,   // s_axi_tx_tkeep
  output logic                     tvalid,  // s_axi_tx_tvalid
  output logic                     tlast    // s_axi_tx_tlast
);
  logic [31:0] seq, lfsr;
  logic [5:0]  wcnt;
  // 32-bit maximal-length LFSR, taps x^32 + x^22 + x^2 + x + 1
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
    end else if (tvalid && tready) begin  // word accepted by the core
      seq  <= seq + 32'd1;
      lfsr <= lfsr_next(lfsr);
      wcnt <= (wcnt == FRAME_LEN-1) ? '0 : wcnt + 6'd1;
    end
  end
endmodule
```

```systemverilog
// lab_checker.sv - BERT-style: locks on first word, predicts every next word
module lab_checker #(
  parameter int PAYLOAD_W = 64
) (
  input  logic                     user_clk,
  input  logic                     rst_n,
  input  logic                     channel_up,
  input  logic [PAYLOAD_W-1:0]     tdata,   // m_axi_rx_tdata
  input  logic [(PAYLOAD_W/8)-1:0] tkeep,   // m_axi_rx_tkeep
  input  logic                     tvalid,  // m_axi_rx_tvalid
  input  logic                     tlast,   // m_axi_rx_tlast
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
      if (!locked) begin                  // adopt first word as seed
        locked <= 1'b1;  seq <= tdata[63:32];  lfsr <= tdata[31:0];
      end else if (tdata !== expected || tkeep !== '1) begin
        error_count <= error_count + 48'd1;  // count, then relock
        seq <= tdata[63:32];  lfsr <= tdata[31:0];
      end else begin
        seq <= exp_seq;  lfsr <= exp_lfsr;
      end
    end
  end
endmodule
```

Run the soak for **at least 5 minutes**. Snapshot both counters with the ILA at start and end and compute the delta. Throughput formula:

```
measured_bps    = delta_words * PAYLOAD_W / elapsed_seconds
payload_ceiling = user_clk * PAYLOAD_W = 156.25 MHz * 64 = 10.0 Gbps
                (equivalently line_rate * 64/66 = 10.3125 * 0.9697)
```

Compute your percentage of ceiling and explain the gap (Aurora framing overhead, tvalid bubbles between frames).

## Part 6: Guided Reading - PCIe Enumeration on the ZCU102 (PetaLinux)

The board's PCIe lives in the PS, not the PL: slot P1 is a x4 Gen2 root port driven by the PS-GTR (about 6 Gb/s class in the Section 5 transceiver table), consuming no PL resources. The board is the host, so Linux observes enumeration from the host side. No hardware purchase is required.

1. Write a prebuilt ZCU102 PetaLinux image to SD, boot, and log in on UART J83 channel 0 at 115200.
2. Run `lspci`, then `lspci -t`; identify the PS-GTR root port (typically 00:00.0), note its vendor/device IDs, and sketch the tree - how many buses exist with no endpoints?
3. Run `lspci -vv -s 00:00.0 | grep -E "LnkCap|LnkSta"` and record both. LnkCap should advertise x4 at 5GT/s (Gen2). With no card installed, what does LnkSta report?
4. Compare LnkCap vs LnkSta the way Section 5's LTSSM slide describes: which is capability, which is negotiated reality?
5. Optional if a PCIe card happens to be on the bench: power off, install it in P1, boot, rerun step 3, and check `dmesg | grep -i pci` for enumeration messages.
6. Reflect: a Gen3/Gen4 card-side endpoint would use PL GTH/GTY and the PCIe hard IP - exactly the resources this lab exercised for Aurora instead.

## Verification Checkpoints

- Part 1: TX_DISABLE shunts installed on SFP0 and SFP1; DAC latched in both cages
- Parts 3-4: ILA rising-edge trigger on lane_up fires; four LEDs mapped; both cores show lane_up then channel_up; time-to-up recorded
- Part 5: soak completed; duration, delta word_count, error_count recorded; throughput computed
- Part 6: LnkCap/LnkSta recorded with a one-sentence interpretation

**Quantitative targets:**

- Both lane_up and channel_up asserted on both cores within seconds of PROGRAM (record the time)
- 0 word errors over a >= 5-minute soak (record duration + final counts)
- Measured throughput within a defensible percentage of the line-rate ceiling: payload efficiency of 64B/66B is 96.97%; compute the theoretical ceiling for your stream width and user clock with the Part 5 formula, then measure and state your ratio

## Conceptual Questions (4)

1. The deck describes commas in 8B/10B for alignment. This link is comma-less. How does a 64B/66B receiver find block boundaries without a comma, and what does it give up or gain?
2. The line rate is 10.3125 Gb/s but the payload ceiling is 10.0 Gbps. Derive the user clock frequency for the 64-bit streaming interface from first principles, and explain why this is the GT/s vs GB/s question in disguise.
3. Why does lane_up assert before channel_up, never the reverse? What layer does each bit summarize?
4. Why is init_clk sourced from the fixed CLK_125 oscillator rather than the programmable Si570 that feeds the GT? Consider reset-domain requirements and what Linux can do to that Si570.

---

**Presented by: Hossam Hassan, PhD**
