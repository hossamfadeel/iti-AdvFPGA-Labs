# Lab 6 Solution — Vitis AI: CNN Inference on the B4096 DPU
**Companion to Section 6: DNN Acceleration on FPGA (Vitis AI/FINN)**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Reference Approach

Pinned 3.0 image and docker throughout; pre-quantized TF ResNet50 from the
v3.0 zoo; vai_c against the ZCU102 B4096 arch JSON; minimal VART runner
cross-compiled from a board-derived sysroot; measurement split into
preprocess, DPU execute, and postprocess.

## Expected Bring-Up Output (abridged, representative)

```
root@xilinx-zcu102-2022_1:~# dexplorer -w
[DNNDK] Target: ZCU102
[DNNDK] DPU IP: DPUCZDX8G     Arch: B4096     Batch: 1
root@xilinx-zcu102-2022_1:~# dmesg | grep -i dpu
[    4.21] dpu <base>.dpu: probing ... 1 core(s)
```

## Expected vai_c Summary (representative)

```
[INFO] Net name: resnet50
[INFO] Total subgraph number : 2  (DPU: 1, CPU: 1)
[INFO] DPU subgraph0 kernel number : 54
[INFO] Total instr byte : ~5.5 MB class
```

## Representative Performance (labeled representative; measure your own)

| Configuration | End-to-end FPS | DPU execute |
| --- | --- | --- |
| 1 thread | ~60-75 | ~4-5 ms |
| 2 threads | ~100-115 | per-job same, pipelined |
| 4 threads | ~130-160 | contention ceiling approached |
| A72 float CPU (if available) | <1 | hundreds of ms |

Monotonic improvement 1->2->4 threads with diminishing returns: the DPU and
DDR are shared. DPU-only throughput ceiling (1/execute-ms) far exceeds
end-to-end FPS; the gap is preprocess and dispatch - exactly the Part 6
analysis point.

## Common Failure Modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| create_runner throws fingerprint/check error | arch JSON mismatch vs board DPU | recompile with the v3.0 ZCU102 JSON; verify against dexplorer |
| Board: error loading libvart-runner.so | environment not sourced / wrong image | use the 3.0 image's preloaded env; check LD_LIBRARY_PATH |
| Garbage outputs or crash in execute | tensor shape/order/batch mismatch | bind buffers exactly as get_shape() reports (NHWC here) |
| Accuracy far below threshold | wrong mean/scale constants | take preprocessing verbatim from the zoo README entry |

## Conceptual Question Answers

1. vai_q: consumes float model + calibration data (host, Python), produces
INT8 quantized graph. vai_c: consumes quantized graph + arch JSON (host),
produces xmodel = DPU instruction stream. VART/XRT: consumes xmodel (board),
loads instructions, drives the DPU and shuttles tensors.
2. PTQ suffices when post-quantization accuracy loss stays within budget
(deck ballpark: typically well under 1% top-1 on standard CNNs). QAT when
accuracy-sensitive architectures or very low bit budgets bite. Evaluating
the quantized model before export catches accuracy collapse while it is
still cheap to iterate.
3. INT8 quarters the activation bytes against FP32 (DDR and snoop traffic)
and packs dense INT8 MACs into the PE array; an A72 spends its cycles on
instruction overhead and float conversions per MAC, while the DPU issues
VLIW-style vector instructions across 4096 MACs per clock.
4. DPU: large standard CNNs (ResNet-class) - VEC engine stress, model zoo
leverage. FINN: tiny deeply-quantized nets (binary/near-binary) at extreme
throughput - the deep pipeline replaces the processor; LOAD/SAVE per layer
become stream plumbing.

## Grading Notes

Full credit requires: version pinning respected everywhere, compile log and
runner logs attached, accuracy table with all images, FPS at 1 and >= 2
thread counts, and the Part 6 time-split written with numbers.

---

**Presented by: Hossam Hassan, PhD**
