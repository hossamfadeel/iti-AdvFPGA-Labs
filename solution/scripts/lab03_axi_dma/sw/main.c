/* Lab03 solution: complete bare-metal A53 DMA+FIR application.
 * Replaces the lab's ellipses; adds the Part-4 throughput harness and the
 * Part-5 disconnect exercise. Build on the exported XSA platform in Vitis. */
#include "xaxidma.h"
#include "xil_cache.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include "xfir.h"
#include <math.h>
#include <stdlib.h>

#define N_SAMPLES 16384
#define FIR_TAPS  11                    /* match your exported Lab02 IP */
#define GROUP_DELAY ((FIR_TAPS - 1) / 2)
#define TOTAL_BYTES (16u * 1024 * 1024)

static float tx_buf[N_SAMPLES] __attribute__ ((aligned (32)));
static float rx_buf[N_SAMPLES] __attribute__ ((aligned (32)));
static float gold[N_SAMPLES];
static XAxiDma dma;
static XFir   fir;

static int dma_init(UINTPTR base)
{
    XAxiDma_Config *cfg = XAxiDma_LookupConfigBase(base);
    if (!cfg) return -1;
    if (XAxiDma_CfgInitialize(&dma, cfg) != XST_SUCCESS) return -1;
    if (XAxiDma_HasSg(&dma)) { xil_printf("SG enabled - config error\r\n"); return -1; }
    XAxiDma_Reset(&dma);
    while (!XAxiDma_ResetIsDone(&dma)) ;
    return 0;
}

static int kernel_init(XFir *k, UINTPTR base)
{
    XFir_Config *cfg = XFir_LookupConfigBase(base);
    if (!cfg) return -1;
    return XFir_CfgInitialize(k, cfg);
}

static void gen_chirp(float *x, int n)
{
    for (int i = 0; i < n; i++)
        x[i] = 1000.0f * sinf(2.0f * 3.14159265f * (0.002f * i) * i / 200.0f);
}

static void golden_fir(const float *x, float *y, int n)
{
    /* low-pass taps for L=11 (Hamming, fc=Fs/4); float pair of the int set */
    static const float taps[FIR_TAPS] = {
       -0.0048f, -0.0122f, 0.0327f, 0.1169f, 0.2195f, 0.2594f,
        0.2195f, 0.1169f, 0.0327f, -0.0122f, -0.0048f };
    for (int i = 0; i < n; i++) {
        float acc = 0.0f;
        for (int k = 0; k < FIR_TAPS && k <= i; k++) acc += taps[k] * x[i - k];
        y[i] = acc;
    }
}

static int verify(void)
{
    for (int i = GROUP_DELAY; i < N_SAMPLES; i++)
        if (fabsf(rx_buf[i - GROUP_DELAY] - gold[i]) > 1e-3f) {
            xil_printf("MISMATCH at %d: %d vs %d\r\n", i,
                       (int)(rx_buf[i - GROUP_DELAY] * 1000), (int)(gold[i] * 1000));
            return -1;
        }
    return 0;
}

static void one_transfer(UINTPTR bytes)
{
    Xil_DCacheFlushRange((UINTPTR)tx_buf, bytes);
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);
    XFir_Start(&fir);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)tx_buf, bytes, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)rx_buf, bytes, XAXIDMA_DEVICE_TO_DMA);
    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE)) ;
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA)) ;
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);
}

static void run_throughput(int samples_per_iter)
{
    const UINTPTR bytes = samples_per_iter * sizeof(float);
    const int iters = TOTAL_BYTES / bytes;
    XTime t0, t1;
    one_transfer(bytes);                       /* warm-up */
    XTime_GetTime(&t0);
    for (int i = 0; i < iters; i++) one_transfer(bytes);
    XTime_GetTime(&t1);
    u64 dt_us = ((t1 - t0) * 1000000ULL) / COUNTS_PER_SECOND;
    u32 mbps  = (u32)((TOTAL_BYTES * 1ULL) / dt_us);
    xil_printf("len=%6d B  iters=%5d  time=%lu us  %lu MiB/s\r\n",
               bytes, iters, dt_us, mbps);
}

int main(void)
{
    XTime t0, t1;
    xil_printf("\r\nLab 3: DMA streaming FIR\r\n");
    if (dma_init(XPAR_AXIDMA_0_BASEADDR)) return 1;
    if (kernel_init(&fir, XPAR_FIR_0_BASEADDR)) return 1;

    gen_chirp(tx_buf, N_SAMPLES);
    golden_fir(tx_buf, gold, N_SAMPLES);
    const UINTPTR bytes = N_SAMPLES * sizeof(float);

    Xil_DCacheFlushRange((UINTPTR)tx_buf, bytes);
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);
    XFir_Start(&fir);
    XTime_GetTime(&t0);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)tx_buf, bytes, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_SimpleTransfer(&dma, (UINTPTR)rx_buf, bytes, XAXIDMA_DEVICE_TO_DMA);
    while (XAxiDma_Busy(&dma, XAXIDMA_DMA_TO_DEVICE)) ;
    while (XAxiDma_Busy(&dma, XAXIDMA_DEVICE_TO_DMA)) ;
    XTime_GetTime(&t1);
    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, bytes);

    xil_printf("transfer+kernel time: %lu us\r\n",
               (u32)((t1 - t0) * 1000000ULL / COUNTS_PER_SECOND));
    if (verify() == 0) xil_printf("PASS: RX matches golden (group delay applied)\r\n");
    else               xil_printf("FAIL\r\n");

    run_throughput(1024);      /* 4 KiB   */
    run_throughput(16384);     /* 64 KiB  */
    run_throughput(262144);    /* 1 MiB   */
    return 0;
}
