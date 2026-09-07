#include "fir.h"
#include <stdio.h>

static acc_t golden_ref(data_t hist[TAPS], data_t xn) {
  for (int i = TAPS - 1; i > 0; --i) hist[i] = hist[i - 1];
  hist[0] = xn;
  acc_t acc = 0;
  for (int i = 0; i < TAPS; ++i) acc += (acc_t)hist[i] * FIR_COEF[i];
  return acc;
}

static uint32_t lcg(void) {
  static uint32_t s = 0x12345678u;
  s = s * 1664525u + 1013904223u;  return s;
}

int main() {
  hls::stream<data_t> in("in");  hls::stream<acc_t> out("out");
  data_t stim[SAMPLES];  data_t hist[TAPS] = {0};  int fail = 0;

  in.write(1);                                    /* Test 1: impulse */
  for (int i = 1; i < SAMPLES; ++i) in.write(0);
  fir_top(in, out);
  for (int i = 0; i < SAMPLES; ++i) {
    acc_t exp = (i < TAPS) ? (acc_t)FIR_COEF[i] : 0;
    if (out.read() != exp && ++fail < 8) printf("IMPULSE FAIL %d\n", i);
  }
  printf("Test 1 (impulse): %s\n", fail ? "FAIL" : "PASS");

  for (int i = 0; i < SAMPLES; ++i) stim[i] = (data_t)(lcg() >> 16);
  for (int i = 0; i < SAMPLES; ++i) in.write(stim[i]);   /* Test 2 */
  fir_top(in, out);
  for (int i = 0; i < SAMPLES; ++i)
    if (out.read() != golden_ref(hist, stim[i]) && ++fail < 8)
      printf("RANDOM FAIL %d\n", i);
  printf("Test 2 (random vs golden): %s\n", fail ? "FAIL" : "PASS");
  if (fail == 0) printf("PASS: fir csim (impulse + random golden)\n");
  return fail ? 1 : 0;
}
