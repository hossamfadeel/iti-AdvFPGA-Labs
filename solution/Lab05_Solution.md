# Lab 5 Solution — Aurora 64B/66B SFP+ Loopback
**Companion to Lab 5: Aurora 64B/66B: 10G Link Between SFP+ Cages**
**Board:** ZCU102 Evaluation Board (XCZU9EG-FFVB1156E) | **Vivado 2023.2**

---

## Expected Bring-Up Observations, In Order

1. PROGRAM via J2 completes. All four status LEDs are dark; the ILA shows lane_up_c0/c1 = 0 and channel_up_c0/c1 = 0. The Si570 on C8/C7 is already running at its 156.25 MHz default - no Si570 programming command is needed from JTAG.
2. Within roughly 1-3 seconds, lane_up_c0 and lane_up_c1 assert (the order between the two cores is arbitrary). Meaning per lane: GT CDR locked and comma-less 64B/66B block sync achieved on valid 2-bit sync headers. The ILA capture triggered on the rising edge of lane_up_c0 shows a single clean transition with no multi-cycle toggling.
3. Less than a second later, channel_up_c0 and channel_up_c1 assert: Aurora protocol initialization validated the channel end to end. LEDs 0-3 all go solid and stay solid indefinitely.
4. With the example-design frame generator/checker still wired: frame_err stays 0 on both receive sides; the ILA shows continuous framed traffic on s_axi_tx with tvalid deasserting for a few cycles between frames; the example checker's PASS indication is steady.
5. After swapping in lab_framer/lab_checker: both checkers lock on the first received word, error_count stays frozen at 0, and word_count free-runs at a rate just below the user clock rate. A retrigger armed on `error_count != 0` never fires during the soak.

Representative time-to-up ledger for the student notebook:

| Event | Representative time after PROGRAM |
| --- | --- |
| PROGRAM done, LEDs dark | t = 0 |
| lane_up, both cores | 1-3 s |
| channel_up, both cores | +0.2-1 s after lane_up |
| Checker lock | first user_clk cycles after channel_up |

## Debug Decision Tables

Runtime symptoms (link will not come up or misbehaves):

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| lane_up never asserts, everything else looks dead | SFP TX_DISABLE jumper header open (they ship OPEN = TX disabled) | Install shunts on SFP0 and SFP1 headers; power cycle |
| lane_up never asserts, jumpers verified | gt_refclk not at 156.25 MHz (Si570 reprogrammed, e.g. to 148.5 MHz for HDMI by a prior Linux boot) | Power cycle the board and run from JTAG; protect the Si570 in the device tree before any Linux use |
| Placer/DRC error naming a GT site | Wrong quad/bank assumed; XAPP1305's erratum prints X0Y4 but the SFP+ quad is really X1Y12-X1Y15 in bank 230 | LOC with GTHE4_CHANNEL_X1Y12 / X1Y13 and re-run implementation |
| lane_up asserts, channel_up never does or flaps | Marginal DAC seating or dirty cage contacts | Reseat both DAC ends; inspect; swap the DAC if suspected |
| channel_up fine, checker reports errors immediately | Endianness or byte-lane wiring mismatch between the two cores | Verify Little-endian on both cores; check tkeep/tdata byte mapping |
| Errors in one direction only | One TX_DISABLE header closed, the other left open | Check both headers - each direction has its own transmitter |

Build-time symptoms (caught before hardware):

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Critical warning: refclk port unconstrained | Missing create_clock on C8 | Add the 6.400 ns period constraint from Part 3 |
| Timing failures crossing init_clk into user clock domains | Missing asynchronous clock groups | Add the set_clock_groups -asynchronous statement |
| Placer error: GT channel overutilized or wrong bank | LOC filter matched nothing (wrong hierarchical pattern) | Run `get_cells -hier *gth_channel*` post-synthesis and fix the filter |

## Representative Soak Result and Throughput Math

Soak duration 300 s (5 minutes), both directions live, PAYLOAD_W = 64:

| Measurement | Value |
| --- | --- |
| error_count, core0 and core1 checkers | 0 |
| delta word_count (one direction) | 42,187,500,000 words |
| delta word_count (other direction) | same, within counter granularity |

Throughput worked through:

```
measured_bps  = delta_words * 64 / elapsed
              = 42,187,500,000 * 64 / 300 = 9.0 Gbps
ceiling_bps   = user_clk * 64 = 156.25 MHz * 64 = 10.0 Gbps
ratio         = 9.0 / 10.0 = 90.0% of payload ceiling
line view     = 10.0 / 10.3125 = 96.97% (the 64B/66B encoding efficiency)
```

The missing 10 percent is Aurora framing overhead plus tvalid gaps between 16-word frames - not encoding loss, which was already paid at 64/66. Widening FRAME_LEN or streaming with fewer inter-frame gaps closes part of it. Students should explain their own measured ratio the same way; anything from roughly 85 to 95 percent of the 10.0 Gbps payload ceiling is a healthy result. A ratio above 96.97 percent of line rate is impossible and means the arithmetic is wrong - a teaching moment, not a victory.

## Conceptual Question Answers

1. Every 66-bit block starts with a 2-bit sync header (01 for data blocks, 10 for control/idle). The receiver tests candidate 66-bit boundaries and locks where headers decode validly; no reserved comma symbol exists. Gain: overhead drops from 25 percent (8B/10B) to 3.03 percent. Give-up: no out-of-band alignment symbol, so block sync is statistical and the scrambler must whiten the payload to keep the headers findable.
2. Payload rate = 10.3125 Gb/s * 64/66 = 10.0 Gb/s exactly. A 64-bit user interface moving one word per cycle therefore needs 10.0e9 / 64 = 156.25 MHz. The gap between 10.3125 GT/s and 10.0 useful Gbps is the encoding tax - the same arithmetic as the deck's 8 GT/s vs 0.98 GB/s worked example.
3. lane_up summarizes the PHY layer per GT channel: CDR lock plus block synchronization, pure transceiver state. channel_up summarizes the protocol layer: Aurora initialization, lane validation, and channel validation complete only after the lanes carry real traffic. The protocol layer depends on the PHY, so the ordering is structural, not a race.
4. init_clk must be free-running and stable whenever the core is sequencing resets - including before the GT and user clocks exist. CLK_125 (G21/F21, bank 47) is a fixed oscillator nothing reprograms; the Si570 is programmable, and under Linux it can be retuned to 148.5 MHz for HDMI unless the device tree protects it, silently corrupting the init/reset domain. Fixed 125 MHz is the robust choice.

## Expected Part 6 Observations (PetaLinux Reading)

Representative shell transcript on a stock prebuilt boot, no card installed:

```
# lspci
00:00.0 PCI bridge: Xilinx Corporation ... Root Port
# lspci -t
-[0000:00]-+-00.0[c0]--
# lspci -vv -s 00:00.0 | grep -E "LnkCap|LnkSta"
LnkCap: Port #0, Speed 5GT/s, Width x4, ASPM L0s L1
LnkSta: Speed 2.5GT/s (downgraded), Width x1 (down)
```

Interpretation students should reach: LnkCap is the PS-GTR root port's *capability* - x4 at Gen2 (5GT/s), matching the deck's ~6 Gb/s PS-GTR class. LnkSta is the *negotiated reality*: with no endpoint in slot P1 the link is down, and the port parks at its floor width/speed. That asymmetry is the whole lesson of the LTSSM slide, observed from the host side without buying a card. If a card is installed, LnkSta should retrain toward the lesser of the two ends' capabilities; a card that trains narrower than LnkCap is a signal-integrity story, not a software one.

## Grading Rubric

| Checkpoint | Pass condition | Weight |
| --- | --- | --- |
| Board prep | Shunts on both TX_DISABLE headers; DAC latched | 10% |
| Design | Both cores at 10.3125 Gbps, Little, X1Y12/X1Y13 LOC'd | 20% |
| Bring-up | lane_up then channel_up on both cores, times recorded | 20% |
| Soak | 0 errors over >= 5 min, duration and counts recorded | 20% |
| Throughput | Correct formula, measured ratio computed and explained | 20% |
| PCIe reading | LnkCap vs LnkSta recorded with a correct interpretation | 10% |

## Instructor Notes

- If DACs are shared across benches, budget two minutes per pair of students for the TX_DISABLE shunt check - it is the overwhelming majority of failed benches.
- error_count nonzero with a rock-solid channel_up is almost always endianness, not signal integrity.
- Enforce the 5-minute minimum soak; overnight runs make a nice optional extension with the same counters.
- Grade the throughput question on the explanation of the gap, not on hitting a specific percentage.

---

**Presented by: Hossam Hassan, PhD**
