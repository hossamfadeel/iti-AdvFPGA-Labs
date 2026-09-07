/* Lab06 solution: minimal VART application (board target).
 * Build inside the Vitis AI 3.0 board image: aarch64 gcc against
 * /usr/include/vart/runner.h -- see scripts/02_board_run.sh */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "vart/runner.h"
#include "xir/graph/xgraph.h"

int main(int argc, char **argv)
{
    if (argc < 3) {
        printf("usage: %s model.xmodel input.bin [iters]\n", argv[0]);
        return 1;
    }
    int iters = (argc > 3) ? atoi(argv[3]) : 100;

    /* 1. load the compiled model */
    auto graph = xir::Graph::deserialize(argv[1]);
    auto runner = vart::Runner::create_runner(graph.get(), "run");
    auto inputs  = runner->get_input_tensors();
    auto outputs = runner->get_output_tensors();

    /* 2. allocate fixed-format buffers */
    size_t in_sz  = inputs[0]->get_data_size().get_element_num()
                  * (inputs[0]->get_data_type() == xir::DataType::INT8 ? 1 : 4);
    size_t out_sz = outputs[0]->get_data_size().get_element_num();
    char *in_buf  = (char *)malloc(in_sz);
    float *out_buf = (float *)malloc(out_sz * sizeof(float));
    FILE *f = fopen(argv[2], "rb");
    if (!f || fread(in_buf, 1, in_sz, f) != in_sz) { printf("input read fail\n"); return 1; }
    fclose(f);

    /* 3. build the job and run it 'iters' times, timing the batch */
    auto job = runner->execute_async(
        {(char *)out_buf}, {(char *)in_buf});
    runner->wait((int)job.first, -1);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (int i = 0; i < iters; i++) {
        auto j = runner->execute_async({(char *)out_buf}, {(char *)in_buf});
        runner->wait((int)j.first, -1);
    }
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double sec = (t1.tv_sec - t0.tv_sec) + 1e-9 * (t1.tv_nsec - t0.tv_nsec);
    printf("top-1 score[0]=%f\n", out_buf[0]);
    printf("throughput: %.1f inf/s (%d iters, %.2f s)\n", iters / sec, iters, sec);
    return 0;
}
