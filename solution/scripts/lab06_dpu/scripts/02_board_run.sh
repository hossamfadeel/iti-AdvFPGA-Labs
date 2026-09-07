#!/usr/bin/env bash
# Lab06: on-board run (run ON the KR260/ZCU102 Vitis AI image, not the host)
set -e
gcc -O2 -std=c++17 -o vart_app ../sw/vart_resnet50.c \
    -I/usr/include/vart -lxir -lvart-runner -lglog || \
  g++ -O2 -std=c++17 -o vart_app ../sw/vart_resnet50.c \
    -I/usr/include -lvart_util -lxir
dpu=x# find your model: /usr/share/vitis_ai_models/... or your compiled xmodel
./vart_app resnet50.xmodel input.bin 200
