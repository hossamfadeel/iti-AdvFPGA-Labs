# Lab 06 -- Vitis AI DPU Deployment: Step-by-Step Solution

**Board + Docker lab.** Complete artifacts: `scripts/lab06_dpu/`
(`sw/vart_resnet50.c`, `scripts/01_docker_compile.sh`, `02_board_run.sh`).

## Step-by-step

### Part 1: bring-up
1. Flash the Vitis AI 3.0 board image (ZCU102 or the K26/KR260 image --
   both have DPU: B4096 vs B2304); boot; `dexplorer -w` shows the DPU
   in /dev/dpu_* (xclbin loaded by the boot firmware).

### Part 2: host toolchain in Docker
2. `./scripts/01_docker_compile.sh` -- two-stage compile in
   xilinx/vitis-ai-cpu:
   - `vai_q_tensorflow`: INT8 calibration (calibration list of ~100 images)
   - `vai_c_tensorflow --arch .../DPUCZDX8G/B4096/arch.json` ->
     `compiled/resnet50.xmodel`
   The arch.json MUST match the board's DPU (B4096 ZCU102 / B2306-class
   K26) -- a mismatched xmodel fails to load on the board.

### Parts 3-5: minimal VART app + measure
3. Build on the board (script provided): compile `vart_resnet50.c`
   against libvart-runner/libxir.
4. The app: deserialize xmodel -> create Runner -> allocate fixed-format
   input (INT8) and float output tensors -> execute_async + wait ->
   print top-1 score and inf/s over 200 iterations.
5. Expected on ZCU102/B4096: ResNet50 INT8 in the 400-600+ inf/s class
   (image-dependent); the number that matters for the course is the
   PL-vs-CPU ratio and the DPU utilization from `dpu.trace` if enabled.

### Part 6: analysis
Compare against Lab02's FIR: two acceleration worlds (dataflow HLS you
control vs a fixed-function NN array you program through a compiler).
Same discipline though: golden input, exact expected output, measured
throughput, and a compile-for-the-target contract.
