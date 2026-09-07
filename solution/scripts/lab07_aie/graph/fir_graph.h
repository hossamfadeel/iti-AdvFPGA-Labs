#pragma once
#include <adf.h>
#include "fir_kernels.h"

// 4-tile FIR cascade: each AIE tile filters one of 4 interleaved phases
// (polyphase decomposition), 256-sample blocks per graph run.
class fir_graph : public adf::graph {
private:
  static const int TAPS = 32;
  int16_t taps[TAPS];
public:
  adf::input_port  in;
  adf::output_port out;
  fir_kernel k0, k1, k2, k3;
  fir_graph(const int16_t (&t)[TAPS]) : k0(t), k1(t), k2(t), k3(t) {
    adf::kernel kern[4] = { adf::kernel::create_object(fir_kernel(t)),
                            adf::kernel::create_object(fir_kernel(t)),
                            adf::kernel::create_object(fir_kernel(t)),
                            adf::kernel::create_object(fir_kernel(t)) };
    for (int i = 0; i < 4; i++) {
      adf::connect< adf::window<512> >(in,  kern[i].in[0]);
      adf::connect< adf::window<512> >(kern[i].out[0], out);
      adf::runtime<ratio>(kern[i]) = 0.5;
    }
  }
};
