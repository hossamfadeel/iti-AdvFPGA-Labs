// V1: + PIPELINE II=1 on TAP
#include "fir.h"
void fir_top(hls::stream<data_t>& in, hls::stream<acc_t>& out) {
#pragma HLS INTERFACE axis port=in
#pragma HLS INTERFACE axis port=out
#pragma HLS INTERFACE s_axilite port=return
    data_t x[TAPS] = {0};
    const coef_t* c = FIR_COEF;
    data_t xn;
    acc_t acc;
MAC: for (int n = 0; n < SAMPLES; ++n) {
        xn = in.read();
    SHIFT: for (int i = TAPS - 1; i > 0; --i) x[i] = x[i - 1];
        x[0] = xn;
        acc = 0;
    TAP: for (int i = 0; i < TAPS; ++i) {
#pragma HLS PIPELINE II=1
            acc += (acc_t)x[i] * c[i];
        }
        out.write(acc);
    }
}
