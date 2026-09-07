# Lab 6 — Vitis AI: CNN Inference on the B4096 DPU
**Companion to Section 6: DNN Acceleration on FPGA (Vitis AI/FINN)**
**Board:** ZCU102 Evaluation Board (XCZU9EG-2FFVB1156E) | **Level:** Intermediate

---

## Introduction

Section 6 presented the Vitis AI stack as a CPU-style toolchain: vai_q is the
front end (FP32 model in, INT8 graph out), the VAI compiler is the back end
(graph in, a DPU instruction stream out), and VART on XRT is the loader that
executes that stream on the DPU - a VLIW-style CNN processor whose LOAD, VEC,
and SAVE engines are scheduled by compiled instructions rather than generated
RTL. This lab walks that complete flow on real hardware: boot the pre-built
Vitis AI ZCU102 image, take a quantized ResNet50 through the compiler, write a
minimal VART C++ application, cross-compile it, and measure classification
accuracy and frames per second on the board's DPUCZDX8G B4096.

The deck's verdict was that FPGAs win on batch-1 latency at the edge. The only
way to believe that number is to produce it yourself and to see where the
milliseconds actually go: preprocess, DPU execute, and softmax are timed
separately in Part 5. The lab closes with the FINN comparison - when the
dataflow alternative to the DPU flow is the right call - and a one-line nod
forward: Section 7's AI Engines are the architectural successor to this exact
MAC math.

## Objectives

- Boot the pinned Vitis AI 3.0 ZCU102 image and verify the DPUCZDX8G B4096 is present.
- Set up the matching host toolchain in docker and understand what each stage consumes and produces.
- Compile a quantized ResNet50 into an xmodel for the B4096 architecture.
- Write, cross-compile, and deploy a minimal VART C++ inference application.
- Verify top-1/top-5 accuracy on a curated image set and record single- and multi-thread FPS.
- Account for where inference time goes, and articulate when FINN is preferred over the DPU flow.

## Prerequisites

- ZCU102 with the shipped 4 GB PS DDR4 SODIMM (J1), micro-USB for serial (J83 channel 0, 115200 8N1) and JTAG (J2), SD card (16 GB+), Ethernet link to the host for scp.
- Host with docker and ~30+ GB free disk.
- Comfort with Linux and basic cross-compilation.

> **Version pinning - read this twice.** The ZCU102 has no Vitis AI board
> image newer than 3.0: UG1354 (v3.5) states ZCU102 pre-builts come from
> Vitis AI 3.0, and later releases ship no DPUCZDX8G updates for this board.
> Pin everything: board image = Vitis AI 3.0 ZCU102; toolchain docker =
> `xilinx/vitis-ai-cpu:3.0`; documentation = UG1414 v3.0 (v3.5 where safe).
> Do NOT follow "latest release" instructions; version mismatch between
> compiler and runtime is the #1 failure mode.

## Part 1: Board Bring-Up with the Vitis AI 3.0 Image

1. **Download and flash:** From the Vitis AI GitHub release tag v3.0.0, download the ZCU102 board image and flash it to SD with balenaEtcher or `dd`.
2. **Set boot mode:** SW6 switch bank, positions 4 through 1 = OFF, OFF, OFF, ON (SD boot).
3. **Boot and log in:** Serial on J83 channel 0 at 115200 8N1; log in as root. The image is a PetaLinux 2022.1-era build with the DPU bitstream baked in - no PL work needed today; this lab is about the software stack.
4. **Verify the DPU:** Run `dexplorer -w` - it must report the DPU IP as DPUCZDX8G, architecture B4096, with the TRD feature set (RAM_USAGE_LOW, CHANNEL_AUGMENTATION_ENABLE, DWCV_ENABLE, POOL_AVG_ENABLE, RELU_LEAKYRELU_RELU6, Softmax). Also `dmesg | grep -i dpu` for the driver probe.
5. **Decode the B-number with Section 6's framing:** B4096 names the PE budget - 4096 INT8 MACs per clock feeding the VEC engine. Multiply by two ops and the PL clock for peak TOPS; the deck's platform table put MPSoC+DPU variants in the 4-26 TOPS class. The feature flags list which ops the compiler may absorb into DPU instructions instead of scheduling on the CPU (depthwise conv, average pooling, leaky ReLU/ReLU6, and on-DPU softmax here).
6. **Network:** `ip addr`, confirm the board and host can reach each other (scp in Part 4).

## Part 2: Host Toolchain in Docker

```bash
docker pull xilinx/vitis-ai-cpu:3.0
docker run -it --shm-size 8g -v $PWD:/workspace xilinx/vitis-ai-cpu:3.0
conda activate vitis-ai-tensorflow      # TF1 env for the ResNet50 entry
```

Inside the container, fetch the model: browse the model zoo listing for
release v3.0 and download the **ResNet50 TensorFlow** package per its README
(float model plus the pre-quantized INT8 model). The recommended path for
this lab is the pre-quantized PTQ artifact - Section 6's ballpark: PTQ costs
hours, not weeks, and typically well under 1% top-1. Optional detour, to see
the front end yourself with a 100-image calibration subset:

```bash
vai_q_tensorflow quantize \
  --input_frozen_graph resnet50_v1.5_float.pb \
  --input_fn calib_input.input_fn \
  --calib_iter 100 \
  --output_dir quant_out
```

## Part 3: Compile for the B4096

The compiler needs the architecture JSON that describes this exact DPU. Do
not trust hardcoded paths - locate it:

```bash
find / -iname "*dpuczdx8g*" 2>/dev/null
find / -iname "*zcu102*.json" 2>/dev/null
```

If the container lacks it, mount a clone of the Vitis-AI repository at tag
v3.0.0 and use `compiler/arch/dpu/DPUCZDX8G/ZCU102/zcu102.json`. Open the
JSON and confirm it describes the B4096 feature set matching `dexplorer`
output from Part 1 - compiler/arch and silicon must agree or the runner
will refuse to load. Then:

```bash
vai_c_tensorflow \
  --frozen_pb quant_out/quantize_eval_model.pb \
  --arch /path/to/zcu102.json \
  --output_dir build \
  --net_name resnet50
```

Read the summary: subgraph count (the DPU subgraph plus any CPU subgraphs),
kernel and instruction byte counts. Section 6's line made literal: your model
is now a program the DPU executes.

## Part 4: A Minimal VART Application

`resnet50_dpu.cpp` (argv: xmodel, image, output scale from the vai_c log):

```cpp
#include <glog/logging.h>
#include <xir/graph/graph.hpp>
#include <vart/runner.hpp>
#include <vart/tensor_buffer.hpp>
#include <opencv2/opencv.hpp>
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <memory>
#include <vector>

int main(int argc, char** argv) {
  auto graph = xir::Graph::deserialize(argv[1]);      /* 1. load  */
  auto root  = graph->get_root_subgraph();
  CHECK_EQ(root->get_children_num(), 1u) << "expected one DPU subgraph";
  auto attrs  = xir::Attrs::create();
  auto runner = vart::Runner::create_runner(root, attrs);

  auto in_t  = runner->get_input_tensors();           /* 2. shapes */
  auto out_t = runner->get_output_tensors();          /* 1x224x224x3 int8 in */
  auto isz   = in_t[0]->get_shape();                  /* 1x1001 int8 out    */
  int h = isz[1], w = isz[2], c = isz[3];
  int nout = out_t[0]->get_shape().back();

  cv::Mat bgr = cv::imread(argv[2], cv::IMREAD_COLOR);
  cv::resize(bgr, bgr, cv::Size(w, h));
  const float mean[3] = {104.0f, 117.0f, 123.0f};   /* from zoo README */
  const float fix_scale = 0.898f;                   /* from zoo README */
  std::vector<int8_t> in(h * w * c), out(nout);
  for (int y = 0; y < h; ++y)
    for (int x = 0; x < w; ++x)
      for (int k = 0; k < c; ++k) {                 /* NHWC, BGR order */
        float v = (bgr.at<cv::Vec3b>(y, x)[k] - mean[k]) * fix_scale;
        in[(y * w + x) * c + k] = (int8_t)std::max(-127.f, std::min(127.f, v));
      }

  auto in_b  = std::make_unique<vart::CpuFlatTensorBuffer>(in.data(),  in_t[0]);
  auto out_b = std::make_unique<vart::CpuFlatTensorBuffer>(out.data(), out_t[0]);
  std::vector<vart::TensorBuffer*> ib{in_b.get()}, ob{out_b.get()};

  auto t0 = std::chrono::steady_clock::now();        /* 3. run, batch 1 */
  auto job = runner->execute_async(ib, ob);
  runner->wait(job.first, -1);
  auto t1 = std::chrono::steady_clock::now();

  const float scale = atof(argv[3]);   /* ranking is scale-invariant;    */
  std::vector<float> logits(nout);     /* scale only affects printed prob */
  for (int i = 0; i < nout; ++i) logits[i] = out[i] * scale;
  std::vector<int> idx(nout);
  for (int i = 0; i < nout; ++i) idx[i] = i;
  std::partial_sort(idx.begin(), idx.begin() + 5, idx.end(),
                    [&](int a, int b){ return logits[a] > logits[b]; });
  for (int i = 0; i < 5; ++i)
    printf("top-%d class %d score %.4f\n", i + 1, idx[i], logits[idx[i]]);
  printf("DPU execute: %.2f ms\n",
         std::chrono::duration<double, std::milli>(t1 - t0).count());
  return 0;
}
```

Cross-compile inside the container against a sysroot taken from the board
(UG1414 approach):

```bash
which aarch64-linux-gnu-g++ || find / -name "aarch64-linux-gnu-g++*" 2>/dev/null
mkdir -p sysroot/usr
scp -r root@<board>:/usr/include               sysroot/usr/
scp -r root@<board>:/usr/lib/aarch64-linux-gnu sysroot/usr/lib/
ls sysroot/usr/include | grep -i -e vart -e xir -e opencv    # sanity
aarch64-linux-gnu-g++ -std=c++14 -O2 resnet50_dpu.cpp -o resnet50_dpu \
  -Isysroot/usr/include -Lsysroot/usr/lib/aarch64-linux-gnu \
  -lxir -lvart-runner -lvart-dpu -lglog -pthread \
  -lopencv_core -lopencv_imgcodecs -lopencv_imgproc
scp resnet50_dpu build/resnet50.xmodel root@<board>:/root/
```

## Part 5: Run, Verify, Measure

1. **Curate a test set:** 10+ JPEGs with unambiguous classes; note expected labels.
2. **Single-image runs:** `./resnet50_dpu resnet50.xmodel img.JPG <scale>`; record top-1/top-5 per image. Expect at least 8/10 top-1 with correct preprocessing; systematic misses mean wrong constants, not DPU failure.
3. **FPS, single thread:** loop the full application (or instrument the loop internally) over N >= 100 iterations; report end-to-end FPS and the printed DPU-execute ms separately.
4. **Stretch, multi-runner:** spawn four threads, each creating its own runner and buffers, submitting concurrently. Note this is not batching - every execution is still a batch-1 graph; you are filling the pipeline, which is exactly the latency-vs-throughput distinction Section 6 drew. Expect monotonic improvement with a contention ceiling.

## Part 6: Analysis

- **Where time goes:** with the timing split (preprocess / DPU / softmax+sort), state which dominates and what you would attack first to improve end-to-end FPS.
- **CPU baseline:** if a float CPU framework is available on the board, measure a frame; otherwise cite Section 6's positioning. Either way, state the two INT8 dividends from the deck: bytes moved (DDR bandwidth) and MACs per cycle (fabric/DPU efficiency).
- **FINN:** in five lines, when would you choose FINN over this DPU flow (tiny quantized nets, dataflow-style throughput, per-layer control) and what do you give up (model zoo, compiler generality)?
- **Forward:** one line - Section 7's AIE array is the hardened version of this story.

## Verification Checkpoints

| Checkpoint | Target | Method |
| --- | --- | --- |
| DPU detected | DPUCZDX8G B4096 reported | dexplorer -w on boot |
| xmodel compiles and loads | create_runner succeeds, single DPU subgraph | Part 3/4 run logs |
| Accuracy | >= 8/10 top-1 on curated set | Part 5 records |
| Timing | DPU-execute ms + end-to-end FPS recorded, 1-thread and 4-thread | chrono prints |

**Quantitative targets:** 1-thread end-to-end FPS and DPU-only ms recorded
(representative class for this configuration: DPU execute around a few
milliseconds; see solution); 4-thread FPS strictly greater than 1-thread;
accuracy threshold as above; every image's top-5 logged.

## Conceptual Questions

1. Map the flow onto Section 6's toolchain analogy: for vai_q, vai_c, and
VART/XRT, state what each consumes, what each produces, and where each runs.
2. The lab used a pre-quantized PTQ model. Using the deck's accuracy
ballpark, when is PTQ sufficient and when must you move to QAT - and what
does evaluating the quantized model before export guard against?
3. Explain, via bytes-moved and MAC-density framing, why INT8 on the DPU
beats the A72 cores by orders of magnitude even at similar clocks.
4. Both the DPU and FINN accelerate quantized convnets. Using the
processor-vs-deep-pipeline framing, give one workload that clearly favors
each, and name the LOAD/VEC/SAVE engine each side would stress.

---

**Presented by: Hossam Hassan, PhD**
