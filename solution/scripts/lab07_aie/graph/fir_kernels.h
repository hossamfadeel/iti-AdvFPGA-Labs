#pragma once
#include <adf.h>

// 32-tap symmetric-decimated FIR window kernel (INT16 x INT16 -> INT32)
class fir_kernel {
public:
  fir_kernel(const int16_t (&taps)[32]);
  void filter(input_window<int16_t>* in, output_window<int32_t>* out);
private:
  int16_t c[32];
};
