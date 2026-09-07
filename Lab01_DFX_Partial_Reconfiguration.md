# Lab 1 — DFX: Runtime Module Swap on ZCU102
**Companion to Section 1: Partial Reconfiguration & DFX**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Advanced

---

## Introduction

Section 1 reframed the bitstream as a runtime object: configuration memory is an
array of addressed frames, and rewriting a subset of frames changes only the
region they cover. The static region (SR), Reconfigurable Partition (RP), and
Reconfigurable Module (RM) vocabulary, the decoupler, and the PCAP load path were
all presented conceptually. This lab makes them physical. You will build a small
Zynq UltraScale+ MPSoC design whose fabric is split into a static region - PS,
free-running counter, AXI GPIO - and one RP holding a "pattern generator". Two
RMs implement the same interface differently: a linear LED chaser (RM-A) and an
LFSR pseudo-random walk (RM-B), tying back to the LFSR work from your intro
course.

You will run the full DFX flow: define the RP and its pblock, implement two
configurations, generate the full bitstream plus two partial bitstreams, swap
partials over JTAG from Hardware Manager, and finally load a partial from the PS
through PCAP using xilfpga - the primary configuration path on this device
family, exactly as Section 1 stated. The proof that DFX works is observability:
while the RP content changes under your feet, the static region must not miss a
beat - the free-running 100 MHz counter and the UART heartbeat keep running
through every swap.

## Objectives

- Build a static region (PS + AXI GPIO + free-running counter) that survives RP swaps unmodified.
- Define an RP with two RMs sharing one interface (clk, rst_n, led[7:0]) and insert a DFX decoupler on the boundary.
- Construct a SystemVerilog testbench (`tb_dfx_behavior.sv`) to simulate boundary decoupling and RM switching prior to hardware implementation.
- Floorplan the RP with a pblock that respects reconfigurable-region snapping rules.
- Generate a full bitstream and two partial bitstreams; verify them with `pr_verify`.
- Swap RMs at runtime from Vivado Hardware Manager and observe static-region continuity.
- Load a partial bitstream from PS DDR through PCAP with `xilfpga` using a production-grade C application, timing the swap with a global timer.
- Troubleshoot common DFX pitfalls using dedicated DRC checks and status register inspections.

## Prerequisites

- Vivado and Vitis 2023.2 (DFX requires a full Vivado license; the standard edition is fine).
- ZCU102 rev 1.0+ (part `xczu9eg-ffvb1156-2-e`, board part `xilinx.com:zcu102:part0:3.3`), USB-UART on micro-USB J83 channel 0 (PS UART0, MIO 18/19, 115200 8N1), JTAG on micro-USB J2.
- Section 1 of the deck read; RP/RM/decoupler vocabulary current.
- Device resources for scale: 274,080 LUTs, 2,520 DSP48E2, 912 BRAM blocks (you will use a tiny slice).

## Part 1: The Static Region

1. **Create Project:** Vivado 2023.2, New Project, select the ZCU102 **board part** (`xilinx.com:zcu102:part0:3.3`) so board presets and the master XDC context apply automatically. Add a new block design `sys.bd`.
2. **Add the PS:** Add the Zynq UltraScale+ MPSoC IP; run **Block Automation** (applies the board preset: DDR4 on SODIMM J1, UART0 on MIO 18/19). In the PS config, enable one GP master (M_AXI_HPM0_FPD) and set FCLK0 = 100 MHz. This FCLK is the fabric clock - free-running, PS-PLL-derived, and by construction outside the RP (Section 1's rule: clocks live in the SR).
3. **Add the AXI GPIO:** Configure `axi_gpio_0` with Channel 1 = output, width 2 (external port `dfx_ctrl[1:0]`: bit 0 = `decouple`, bit 1 = `rm_rst_n`, active-low) and Channel 2 = input, width 32 (external port `hb_count[31:0]`). Run Connection Automation for the AXI interface and clock/reset.
4. **Add the heartbeat counter:** Create `rtl/heartbeat_ctr.sv` and add it as a **module reference** (this one stays static):

```systemverilog
module heartbeat_ctr (
  input  logic        clk,      // 100 MHz FCLK0
  output logic [31:0] count     // free-running, never reset
);
  always_ff @(posedge clk) count <= count + 32'd1;
endmodule
```

5. **Wire the counter:** Connect `count` to the GPIO Channel 2 input. The PS will read this counter before and after every swap: if it kept counting at 100 MHz, the static fabric was never disturbed.
6. **Heartbeat software:** In Vitis later, the A53 application prints a UART heartbeat and polls `hb_count`; both must continue through RP swaps.

## Part 2: The Reconfigurable Partition and Its RMs

1. **Write the two RMs** with identical interfaces (identical interfaces are what makes them interchangeable):

```systemverilog
// rtl/pattern_chaser.sv  (RM-A)
module pattern_chaser (
  input  logic       clk,
  input  logic       rst_n,
  output logic [7:0] led
);
  logic [27:0] div = '0;           // ~2.68 s period
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      div <= '0;  led <= 8'b0000_0001;
    end else begin
      div <= div + 1'b1;
      if (div[21]) begin           // step every ~4.2 ms
        div  <= '0;
        led  <= {led[6:0], led[7]}; // 1-of-8 rotate
      end
    end
  end
endmodule

// rtl/pattern_lfsr.sv  (RM-B)
module pattern_lfsr (
  input  logic       clk,
  input  logic       rst_n,
  output logic [7:0] led
);
  logic [27:0] div = '0;
  logic [7:0] lfsr = 8'hAC;        // nonzero seed
  always_ff @(posedge clk or negedge rst_n)
    if (!rst_n) begin
      div <= '0;  lfsr <= 8'hAC;
    end else begin
      div <= div + 1'b1;
      if (div[21]) begin
        div  <= '0;
        lfsr <= {lfsr[6:0], 
                 lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        led  <= lfsr;
      end
    end
endmodule
```

2. **Add the RP:** Add `pattern_chaser` to the block design as a module reference named `u_pattern` (right-click canvas, **Add Module**). Connect `clk` = FCLK0, `rst_n` = `dfx_ctrl[1]`, and make `led[7:0]` external.
3. **Insert the decoupler:** Open **Tools -> Dynamic Function eXchange Wizard**. Enable DFX for the design, select `u_pattern` as the reconfigurable partition, and on the decoupler page enable decoupling for the `led` output with safe value 0x00. The wizard inserts a `dfx_decoupler` in static between `u_pattern.led` and the outside world. Connect its `decouple` control to `dfx_ctrl[0]`. Why decouple at all, when the only consumer is LEDs and an AXI-read GPIO? Because the RP outputs are undefined during the frame rewrite - Section 1's rule is to hold any observed boundary to a safe value, and here it also gives a clean visual: assert `decouple`, LEDs go dark and stay dark, release, new pattern appears.
4. **Constrain the LEDs** in `constr/leds.xdc` (master-XDC entries for these pins stay inactive; board flow does not constrain your custom ports):

```tcl
set_property -dict {PACKAGE_PIN AG14 IOSTANDARD LVCMOS33} \
  [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN AF13 IOSTANDARD LVCMOS33} \
  [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN AE13 IOSTANDARD LVCMOS33} \
  [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN AJ14 IOSTANDARD LVCMOS33} \
  [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN AJ15 IOSTANDARD LVCMOS33} \
  [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN AH13 IOSTANDARD LVCMOS33} \
  [get_ports {led[5]}]
set_property -dict {PACKAGE_PIN AH14 IOSTANDARD LVCMOS33} \
  [get_ports {led[6]}]
set_property -dict {PACKAGE_PIN AL12 IOSTANDARD LVCMOS33} \
  [get_ports {led[7]}]
```

5. **Behavioral Simulation Testbench:** To verify the decouple boundary logic and RM reset sequencing prior to synthesis, create `tb/tb_dfx_behavior.sv`:

```systemverilog
`timescale 1ns / 1ps

module tb_dfx_behavior;
  logic        clk = 0;
  logic        rm_rst_n = 0;
  logic        decouple = 0;
  logic [7:0]  rm_led;
  logic [7:0]  decoupled_led;
  logic [31:0] hb_count;

  // 100 MHz clock generation
  always #5 clk = ~clk;

  // Instantiate static heartbeat counter
  heartbeat_ctr u_hb (
    .clk(clk),
    .count(hb_count)
  );

  // Instantiate RM-A (Chaser)
  pattern_chaser u_rm_a (
    .clk(clk),
    .rst_n(rm_rst_n),
    .led(rm_led)
  );

  // Decoupler representation (safe value = 0x00)
  assign decoupled_led = decouple ? 8'h00 : rm_led;

  initial begin
    $display("[TB] Starting DFX Behavioral Verification...");
    
    // Step 1: Assert Reset & Decouple
    decouple = 1;
    rm_rst_n = 0;
    #100;
    
    assert(decoupled_led == 8'h00) else 
      $error("[TB ERROR] LEDs not zero in decouple state!");
    
    // Step 2: Release Reset & Release Decouple
    rm_rst_n = 1;
    #20;
    decouple = 0;
    $display("[TB] Decouple released. Initial RM-A: %b", 
             decoupled_led);
    
    // Step 3: Run for several clock cycles
    #1000;
    assert(hb_count > 32'd100) else 
      $error("[TB ERROR] Heartbeat counter stalled!");
    
    // Step 4: Simulate Runtime Swap Sequence
    $display("[TB] Initiating Reconfiguration Sequence...");
    decouple = 1;      // Quiesce boundary
    rm_rst_n = 0;      // Assert RM reset
    #500;              // Partial bitstream window
    
    assert(decoupled_led == 8'h00) else 
      $error("[TB ERROR] Glitch on LED boundary!");
    
    // Step 5: Complete Swap Sequence
    rm_rst_n = 1;
    decouple = 0;
    $display("[TB] Reconfig complete. LED: %b, HB: %d", 
             decoupled_led, hb_count);
    
    $display("[TB] Behavioral Verification Passed!");
    $finish;
  end
endmodule
```

## Part 3: RP Definition and Pblock

1. **Generate and synthesize:** Validate the design, generate output products (global synthesis for the static portion), and open the synthesized design.
2. **Mark the RP:** In the Tcl console:

```tcl
set_property HD.RECONFIGURABLE 1 [get_cells u_pattern]
```

3. **Draw the pblock:** With `u_pattern` selected, use **Draw Pblock** to create a rectangle, then apply **SNAP_TO_GRID** and reconfigurable-region guides. Two rules from Section 1 made concrete: clock-region aligned edges (Vivado will resize to legal boundaries - accept), and the pblock must not clip I/O sites or clocking resources.

```tcl
create_pblock pblock_u_pattern
resize_pblock pblock_u_pattern \
  -add {CLOCKREGION_X1Y2:CLOCKREGION_X1Y2}
add_cells_to_pblock pblock_u_pattern \
  [get_cells u_pattern]
set_property CONTAIN_ROUTING true \
  [get_pblocks pblock_u_pattern]
```

One clock region is far more than this RM needs - deliberately, so you can watch partial size track pblock area, not logic content.

## Part 4: Two Configurations, Three Bitstreams

1. **Config A (chaser):** With `pattern_chaser` as the module reference content, run implementation, then:

```tcl
write_checkpoint config_a/routed.dcp
write_bitstream config_a/full_chaser.bit
write_bitstream config_a/partial_chaser_to_lfsr.bit \
  -cell u_pattern
```

2. **Config B (LFSR):** Out-of-context synth the second RM, then stitch it into the frozen static:

```tcl
synth_design -top pattern_lfsr -mode out_of_context
write_checkpoint rm_lfsr_synth.dcp
open_checkpoint config_a/routed.dcp
read_checkpoint -cell u_pattern rm_lfsr_synth.dcp
opt_design; place_design; route_design
pr_verify config_a/routed.dcp
write_checkpoint config_b/routed.dcp
write_bitstream config_b/full_lfsr.bit
write_bitstream config_b/partial_lfsr_to_chaser.bit \
  -cell u_pattern
```

3. **Record file sizes:** Note the byte size of `full_chaser.bit` and of both partials. The partial size should be a small, stable fraction of the full bitstream, tracking the pblock area - not the RM content. Two RMs of different logic but the same pblock produce near-identical partial sizes. Check this; it is Section 1's "size is a floorplan property" claim in your file manager.

## Part 5: Swap Over JTAG from Hardware Manager

1. **Program the full bitstream** `full_chaser.bit` via the Hardware Manager (JTAG J2). Observe the linear chase on GPIO_LED[7:0] and the UART heartbeat ticking on your terminal.
2. **Swap to RM-B:** Right-click the device, **Program Device**, and select `partial_lfsr_to_chaser.bit`. Do not touch the PS or the running program. Within a second or two the LEDs switch from the one-hot rotation to the pseudo-random walk. The UART heartbeat never pauses; read `hb_count` over AXI before and after - the delta matches elapsed time at 100 MHz.
3. **Swap back:** Load `partial_chaser_to_lfsr.bit`. The chase returns.
4. **Watch the decoupler:** In the Vitis app, assert `decouple` (GPIO ch1 bit 0): LEDs freeze at the safe value 0x00. Release: pattern returns. During Hardware-Manager swaps nobody asserts decouple - observe whatever transitional behavior appears on the LEDs and explain it against Section 1's "outputs are garbage during rewrite" warning.

## Part 6: Swap from the PS Through PCAP

1. **Convert the partial to a bin** the CSU can stream:

```tcl
bootgen -image partial_lfsr_to_chaser.bit \
        -arch zynqmp \
        -o partial_lfsr.bin \
        -w -process_bitstream bin
```

2. **Complete Vitis Application (`main.c`):** Create the full standalone C application in Vitis targeting ARM Cortex-A53:

```c
#include <stdio.h>
#include <stdlib.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include "xilfpga.h"

// Hardware Base Addresses and Device IDs
#define GPIO_DEVICE_ID     XPAR_AXI_GPIO_0_DEVICE_ID
#define PARTIAL_BIN_ADDR   0x10000000 // DDR Location (~1.5 MB)
#define PARTIAL_SIZE_BYTES 0x00180000 // Partial bin size

// Bit positions for GPIO Control Channel
#define MASK_DECOUPLE      0x01 // Bit 0: Decouple signal
#define MASK_RM_RST_N      0x02 // Bit 1: Active-low Reset

static XGpio Gpio;

u32 read_heartbeat(void) {
    return XGpio_DiscreteRead(&Gpio, 2);
}

void set_dfx_ctrl(u32 decouple, u32 rm_rst_n) {
    u32 reg_val = 0;
    if (decouple)  reg_val |= MASK_DECOUPLE;
    if (rm_rst_n)  reg_val |= MASK_RM_RST_N;
    XGpio_DiscreteWrite(&Gpio, 1, reg_val);
}

int main(void) {
    int status;
    XFpga XFpgaInstance = {0};
    XTime tStart, tEnd;
    u32 hb_start, hb_end;
    double elapsed_us;

    xil_printf("\r\n===================================\r\n");
    xil_printf(" ZCU102 DFX PCAP Swap Controller  \r\n");
    xil_printf("===================================\r\n");

    // 1. Initialize AXI GPIO Driver
    status = XGpio_Initialize(&Gpio, GPIO_DEVICE_ID);
    if (status != XST_SUCCESS) {
        xil_printf("[ERROR] AXI GPIO Init Failed (%d)\r\n",
                   status);
        return XST_FAILURE;
    }

    // Set Ch 1 output (ctrl), Ch 2 input (heartbeat)
    XGpio_SetDataDirection(&Gpio, 1, 0x00);
    XGpio_SetDataDirection(&Gpio, 2, 0xFFFFFFFF);

    // Initial State: Decouple disabled, Reset released
    set_dfx_ctrl(0, 1);
    xil_printf("[INIT] Static Region Alive. HB = %u\r\n",
               read_heartbeat());

    // 2. Initialize xilfpga PCAP library
    status = XFpga_Initialize(&XFpgaInstance);
    if (status != XFPGA_SUCCESS) {
        xil_printf("[ERROR] XFpga_Init Failed: 0x%X\r\n",
                   status);
        return XST_FAILURE;
    }

    xil_printf("[INFO] Ready for Partial Load over PCAP.\r\n");

    // 3. Execution of Handshake & Reconfig Loop
    for (int run = 1; run <= 5; run++) {
        xil_printf("\r\n--- Starting DFX Swap #%d ---\r\n",
                   run);

        hb_start = read_heartbeat();

        // STEP 1: Quiesce RM (Assert Reset)
        xil_printf("[STEP 1] Quiescing RM...\r\n");
        set_dfx_ctrl(0, 0);

        // STEP 2: Decouple Boundary
        xil_printf("[STEP 2] Asserting decoupler...\r\n");
        set_dfx_ctrl(1, 0);

        // STEP 3: Load Partial Bitstream via PCAP
        xil_printf("[STEP 3] Triggering PCAP (0x%08X)...\r\n",
                   PARTIAL_BIN_ADDR);
        XTime_GetTime(&tStart);
        
        status = XFpga_PartialBtcnfg(&XFpgaInstance, 
                                     (UINTPTR)PARTIAL_BIN_ADDR, 
                                     PARTIAL_SIZE_BYTES, 
                                     XFPGA_PARTIAL_BITMAP);
        
        XTime_GetTime(&tEnd);

        if (status != XFPGA_SUCCESS) {
            xil_printf("[ERROR] PCAP failed! Code: 0x%X\r\n",
                       status);
            set_dfx_ctrl(0, 1);
            return XST_FAILURE;
        }

        elapsed_us = (double)(tEnd - tStart) * 1000000.0 / 
                     COUNTS_PER_SECOND;
        xil_printf("[SUCCESS] Bitstream written in %.2f us.\r\n",
                   elapsed_us);

        // STEP 4: Release Reset on New RM
        xil_printf("[STEP 4] Releasing RM reset...\r\n");
        set_dfx_ctrl(1, 1);

        // STEP 5: Recouple Boundary
        xil_printf("[STEP 5] Recoupling boundary...\r\n");
        set_dfx_ctrl(0, 1);

        hb_end = read_heartbeat();
        xil_printf("[VERIFY] Heartbeat delta = %u ticks\r\n", 
                   (hb_end - hb_start));
    }

    xil_printf("\r\n[DONE] All 5 PCAP swaps completed.\r\n");
    return 0;
}
```

3. **The handshake sequence rules in detail:**
   - **Quiesce RM:** Hold `rm_rst_n` low to ensure no state updates happen inside the RP during bitstream transfer.
   - **Decouple boundary:** Assert `decouple` to prevent unknown floating signals/glitches inside the RP from propagating into the static fabric or external pins.
   - **PCAP Transfer:** Call `XFpga_PartialBtcnfg()` which programs configuration frames directly through the Configuration Security Unit (CSU) DMA.
   - **Release Reset & Recouple:** Release `rm_rst_n` to initialize the fresh RM state, then clear `decouple` to expose the new outputs.

4. **Stress testing static region independence:**
   - Execute continuous swaps in a loop while monitoring the UART heartbeat output.
   - Read `hb_count` across multiple swaps; verify that the counter increases continuously without resetting or skipping cycles.

## Verification Checkpoints

| Checkpoint | Target | Method |
| --- | --- | --- |
| Full bitstream boots | chaser pattern + UART heartbeat | Visual + terminal |
| Partial sizes | near-identical for both RMs, small fraction of full | `ls -l` on the three bitstreams |
| Behavioral Simulation | Testbench executes cleanly without assertions | `xsim` simulation log |
| Static continuity over JTAG swap | heartbeat pauses 0 times; hb_count delta matches elapsed time | UART log + GPIO reads around swap |
| PCAP swap status | `XFPGA_SUCCESS` on 10/10 swaps in both directions | application return codes |
| PCAP swap time | recorded, in the expected class for a 1-clock-region RP | global-timer print (tens of ms class; record your value) |
| Decoupler function | LEDs held at 0x00 while decouple asserted | GPIO write + visual |

**Quantitative targets:** Partial bitstreams for both RMs within ~10% of each other in size and both well under 10% of the full bitstream (record exact bytes); PCAP swap wall time per the global timer with min/max over ten runs; hb_count monotonic increase across every swap with rate 100 MHz within measurement noise (record the largest deviation).

## Troubleshooting & Common Pitfalls

### 1. Vivado `pr_verify` Failures
- **Symptom:** `ERROR: [Vivado 12-4411] pr_verify failed due to routing or placement discrepancies between static region implementations.`
- **Cause:** The static region modified between Configuration A and Configuration B, or signals crossing the RP boundary were modified without freezing static placement/routing.
- **Fix:** Always start Config B by loading the routed design checkpoint of Config A (`config_a/routed.dcp`), locking the static region with `lock_design -level routing`, and replacing only the cell instance using `read_checkpoint -cell u_pattern rm_lfsr_synth.dcp`.

### 2. Pblock Resource Alignment Rules
- **Symptom:** `ERROR: [HD 12-3211] Pblock pblock_u_pattern does not satisfy reconfigurable region grid alignment rules.`
- **Cause:** UltraScale+ DFX pblocks must align to complete CLB clock region tiles and must not intersect prohibited resources (such as hard IP, GTH transceivers, or I/O banks) unless explicit boundary rules are set.
- **Fix:** In Vivado GUI, right-click the pblock and select **Tools -> Pblock -> Apply Grid Alignment (SNAP_TO_GRID)**. Ensure `CONTAIN_ROUTING` and `EXCLUDE_PLACEMENT` properties are correctly enabled.

### 3. PCAP Bitstream Delivery Failures (`XFPGA_SUCCESS` returns error code)
- **Symptom:** `XFpga_PartialBtcnfg` returns error codes `0x02` (xilfpga initialization fail) or `0x0A` (CSU DMA transfer error).
- **Cause:** 
  1. The bitstream was not converted to `.bin` format using `bootgen`.
  2. The DDR memory address holding the bitstream is not aligned or was overwritten.
  3. The `-process_bitstream bin` parameter was omitted during `bootgen` invocation.
- **Fix:** Re-run `bootgen`: `bootgen -image partial.bit -arch zynqmp -o partial.bin -w -process_bitstream bin`. Verify in Vitis debugger that memory at `PARTIAL_BIN_ADDR` contains the sync word `0xAA995566`.

### 4. Boundary Glitches & Decoupling Errors
- **Symptom:** Static region logic enters an undefined state or external peripherals reset during an active RP swap.
- **Cause:** Decoupler asserted too late (after partial bitstream configuration initiated) or not asserted at all.
- **Fix:** Enforce the strict 5-step software handshake in `main.c`: **Reset RM -> Decouple -> Load Bitstream -> Release Reset -> Recouple**.

## Conceptual Questions

1. Both partial bitstreams are nearly the same size even though the LFSR and chaser differ internally. Explain in terms of frames and the pblock why content does not drive size, and what would happen to partial size if you doubled the pblock while keeping the RM identical.
2. Why must clocks, resets, and PS interfaces live in the static region? Trace what would break during a swap if the 100 MHz clock buffer were inside the RP.
3. The partials are paired with exactly one static build. What exactly goes wrong if you load a partial generated against a different static implementation, and which mechanism (from Section 1's list) is meant to catch it?
4. Your PCAP timing measurement includes CSU overhead beyond pure frame writes. Propose an experiment on this same design to separate configuration-frame time from fixed software overhead.

---

**Presented by: Hossam Hassan, PhD**
