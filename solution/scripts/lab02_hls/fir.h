#ifndef FIR_H
#define FIR_H
#include <stdint.h>
#include <hls_stream.h>

#define TAPS     128
#define SAMPLES  1024

typedef int16_t data_t;
typedef int16_t coef_t;
typedef int32_t acc_t;

static const coef_t FIR_COEF[TAPS] = {
  -18,-16,-12, -8, -2,  4, 11, 18, 25, 31, 36, 40, 43, 44, 43, 40,
   36, 30, 23, 15,  6, -3,-12,-20,-27,-32,-35,-36,-34,-30,-24,-16,
   -8,  0,  9, 16, 22, 26, 28, 28, 26, 22, 16,  9,  1, -7,-14,-19,
  -23,-24,-23,-20,-16,-10, -4,  3,  9, 14, 18, 20, 21, 19, 16, 12,
    6,  0, -5, -9,-12,-13,-12,-10, -7, -3,  0,  3,  6,  8,  9,  9,
    8,  6,  4,  1, -1, -4, -6, -7, -8, -8, -7, -5, -3,  0,  1,  3,
    5,  6,  6,  6,  5,  4,  2,  0, -1, -3, -4, -5, -5, -5, -4, -3,
   -2,  0,  1,  2,  3,  3,  3,  3,  2,  1,  0, -1, -1, -2, -2, -2
};
void fir_top(hls::stream<data_t>& in, hls::stream<acc_t>& out);

#endif
