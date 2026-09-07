#!/usr/bin/env bash
# Lab06: host-side model compilation in the Vitis AI docker (needs Docker)
set -e
docker run --rm -v "$PWD:/work" -w /work \
  -e USER=$(id -u) -e GROUP=$(id -g) \
  xilinx/vitis-ai-cpu:latest \
  bash -c "conda activate vitis-ai && \
           vai_q_tensorflow --input_frozen_graph frozen.pb \
             --input_fn input_fn.calib --output_dir quant --input_nodes input \
             --output_nodes resnet_v1_50/predictions/Reshape_1 --quantize_input_image; \
           vai_c_tensorflow --frozen_pb quant/quantize_eval_model.pb \
             --arch /opt/vitis_ai/compiler/arch/DPUCZDX8G/B4096/arch.json \
             --output_dir compiled --net_name resnet50"
echo "compiled/resnet50.xmodel is the board artifact"
