# Lab 1 Solution — DFX: Runtime Module Swap on ZCU102
**Companion to Section 1: Partial Reconfiguration & DFX**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Advanced

---

## Reference Approach

Static region: PS (UART0 heartbeat prints, GP0 master, FCLK0 100 MHz), AXI GPIO
(ch1 = 2-bit swap control, ch2 = 32-bit counter window), free-running counter,
DFX decoupler on the RP `led` boundary, user XDC on GPIO_LED[7:0]. RP
`u_pattern` in one clock region; RM-A chaser, RM-B LFSR; two configurations via
checkpoint stitching with pr_verify; swaps over JTAG then PCAP via xilfpga.

## Expected Observations Per Part

**Part 4 - bitstream sizes (representative):** full bitstream on the order of
tens of MB class for XCZU9EG; partials roughly 1-3% of full, and the two
partials within a few percent of each other. The teaching point is the
relationship (size tracks pblock, not RM content), not the absolute bytes -
students record their own numbers. A pblock doubled in area roughly doubles the
partial regardless of RM logic.

**Part 5 - JTAG swap:** the console heartbeat (1 print/s) shows zero gaps
across the swap; hb_count deltas before/after match wall time at 100 MHz
within poll granularity. Transitional LED behavior during the swap window is
expected and becomes deterministic garbage only while frames are mid-rewrite;
students should connect it to the decouple discipline rather than treat it as
a fault.

**Part 6 - PCAP swap (representative):** status XFPGA_SUCCESS on every swap;
per-swap time from the global timer in the tens-of-milliseconds class for a
single-clock-region RP (record min/max over 10; expect a tight spread).
hb_count monotonic throughout.

## Common Failure Modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| DRC: RP overlaps I/O or clock sites | pblock clipped illegal resources | accept snap/resize; keep clock-region aligned edges |
| Partial loads, design dies | static element inside RP frames | check HD.RECONFIGURABLE target; clocks/resets/PS must be static |
| Decoupler never engages | control tied to wrong GPIO bit | dfx_ctrl[0] = decouple, dfx_ctrl[1] = rm_rst_n (active-low) |
| PCAP returns error status | wrong bin (raw .bit fed to CSU) | bootgen -process_bitstream bin, load the .bin |
| UART dies during swap | heartbeat depends on PL logic inside RP | PS-only heartbeat or move logic to static |

## Conceptual Question Answers

1. Configuration memory is addressed in frames; a partial covers exactly the
frames of its pblock. RM content changes bit values inside those frames, not
the frame count. Doubling the pblock doubles frames, hence roughly doubles the
partial, even for identical logic.
2. During the rewrite the RP's clocking and routing are in flux. A BUFG inside
the RP would glitch the clock mid-swap, corrupting every downstream FF -
including static consumers. The fixed boundary must carry only clean, static
driven clocks/resets into the RP.
3. The static's placed/routed boundary nets and frame addresses assume one
static implementation; a foreign partial's port placement or frame layout
misaligns and corrupts the RP. pr_verify (run in Part 4) is the guard: it
compares configurations for exactly this compatibility.
4. Swap RMs of identical pblock but measure across a doubled pblock (Part 3's
extension): the delta in frame time isolates per-frame cost; alternatively time
back-to-back swaps with no software re-initialization between them to expose
fixed overhead.

## Grading Notes

Full credit requires: both partials generated against the same static
(pr_verify clean), ten successful PCAP swaps with recorded timings, hb_count
continuity evidence, and the size-relationship observation written down with
actual numbers.

---

**Presented by: Hossam Hassan, PhD**
