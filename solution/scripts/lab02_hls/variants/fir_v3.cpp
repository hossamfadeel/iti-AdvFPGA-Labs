// V3: ARRAY_PARTITION + UNROLL: one MAC per tap per cycle
#include "fir.h"
static void compute(hls::stream<data_t>& s, hls::stream<acc_t>& r) {
#pragma HLS ARRAY_PARTITION variable=FIR_COEF complete
    data_t x[TAPS] = {0};
#pragma HLS ARRAY_PARTITION variable=x complete dim=1
    const coef_t* c = FIR_COEF;
    data_t xn;
    acc_t acc;
LOOP_SAMPLE: for (int n = 0; n < SAMPLES; ++n) {
#pragma HLS PIPELINE II=1
        xn = s.read();
    SHIFT: for (int i = TAPS - 1; i > 0; --i) x[i] = x[i - 1];
        x[0] = xn;
        acc = 0;
    TAP: for (int i = 0; i < TAPS; ++i) {
#pragma HLS UNROLL factor=TAPS
            acc += (acc_t)x[i] * c[i];
        }
        r.write(acc);
    }
}
static void load(hls::stream<data_t>& in, hls::stream<data_t>& s) {
LOAD: for (int n = 0; n < SAMPLES; ++n) s.write(in.read());
}
static void store(hls::stream<acc_t>& r, hls::stream<acc_t>& out) {
STORE: for (int n = 0; n < SAMPLES; ++n) out.write(r.read());
}
void fir_top(hls::stream<data_t>& in, hls::stream<acc_t>& out) {
#pragma HLS INTERFACE axis port=in
#pragma HLS INTERFACE axis port=out
#pragma HLS INTERFACE s_axilite port=return
#pragma HLS DATAFLOW
    static hls::stream<data_t> s("s");
    static hls::stream<acc_t>  r("r");
#pragma HLS STREAM variable=s depth=4
#pragma HLS STREAM variable=r depth=4
    load(in, s);  compute(s, r);  store(r, out);
}
