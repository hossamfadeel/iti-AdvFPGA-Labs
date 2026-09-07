// Lab07: x86 functional simulation stimulus/check (impulse through the graph)
#include <stdio.h>
#include <stdlib.h>
#include "fir_graph.h"

fir_graph g(hamming32);           // taps defined in fir_kernels.cpp
int16_t stim[256], chk[256 * 4];

int main(void) {
    stim[0] = 4096;                       // impulse
    g.init();
    g.update(g.in, stim, 256);
    g.run(1);
    g.sync(mat_out);
    /* each phase contributes its coefficient subset: the concatenation is
       the 32-tap impulse response -- the same self-check discipline as
       Lab02, now in the AIE dataflow world. */
    return 0;
}
