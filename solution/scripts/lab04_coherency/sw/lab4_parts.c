/* Lab04 solution: the three datapoint programs as ONE app with a selector.
 * Uses Lab03 helpers (fill_fir_input = gen_chirp; dma_fir_once = one_transfer;
 * golden = golden_fir) -- see ../lab03_axi_dma/sw/main.c for the complete
 * implementations referenced here. Run part1..part4 from main() in turn. */
#include "xil_cache.h"
#include "xil_printf.h"
#include "xtime_l.h"
#include <string.h>

#define BUF_BYTES  (64 * 1024)
#define STALE_BYTE 0xA5
#define LINE       64

extern void fill_fir_input(u8 *tx, u32 len);          /* Lab03 helpers */
extern void dma_fir_once(u8 *tx, u8 *rx, u32 len);
extern const u8 *golden_fir_output(void);

static u8 tx[BUF_BYTES] __attribute__ ((aligned (LINE)));
static u8 rx[BUF_BYTES] __attribute__ ((aligned (LINE)));

static void prime_both_bugs(void)
{
    memset(rx, STALE_BYTE, BUF_BYTES);
    fill_fir_input(tx, BUF_BYTES);
    /* DELETED (this is the point):
     *   Xil_DCacheFlushRange((UINTPTR)tx, BUF_BYTES);
     *   Xil_DCacheInvalidateRange((UINTPTR)rx, BUF_BYTES);            */
}

static int verify_rx(u32 len, u32 *first_bad, u32 *stale_lines)
{
    const u8 *gold = golden_fir_output();
    u32 n = 0, off;
    *stale_lines = 0;
    for (off = 0; off < len; off += LINE)
        if (memcmp(rx + off, gold + off, LINE) != 0) {
            if (n == 0) *first_bad = off;
            if (rx[off] == STALE_BYTE) (*stale_lines)++;
            n++;
        }
    return n;
}

void lab4_part1(void)   /* HP0, maintenance removed: EXPECT bad lines */
{
    u32 first = 0, stale = 0;
    prime_both_bugs();
    dma_fir_once(tx, rx, BUF_BYTES);
    xil_printf("part1 bad lines %d/%d, first at line %d, stale %d\r\n",
               verify_rx(BUF_BYTES, &first, &stale),
               BUF_BYTES / LINE, first / LINE, stale);
}

void lab4_part2(void)   /* HP0, maintenance restored: EXPECT 0 bad lines */
{
    u32 first = 0, stale = 0;
    fill_fir_input(tx, BUF_BYTES);
    memset(rx, STALE_BYTE, BUF_BYTES);
    Xil_DCacheFlushRange((UINTPTR)tx, BUF_BYTES);
    Xil_DCacheInvalidateRange((UINTPTR)rx, BUF_BYTES);
    dma_fir_once(tx, rx, BUF_BYTES);
    Xil_DCacheInvalidateRange((UINTPTR)rx, BUF_BYTES);
    xil_printf("part2 bad lines %d (expect 0)\r\n",
               verify_rx(BUF_BYTES, &first, &stale));
}

static u32 time_maintenance(u32 len)   /* us */
{
    XTime t0, t1;
    XTime_GetTime(&t0);
    Xil_DCacheFlushRange((UINTPTR)tx, len);
    Xil_DCacheInvalidateRange((UINTPTR)rx, len);
    XTime_GetTime(&t1);
    return (u32)((t1 - t0) * 1000000ULL / COUNTS_PER_SECOND);
}

void lab4_part2_timing(void)
{
    for (int ki = 2; ki <= 8; ki += 2) {   /* 4,16,64,256 KiB */
        u32 len = 1024u << ki;
        u32 avg = 0;
        for (int i = 0; i < 100; i++) avg += time_maintenance(len);
        xil_printf("maintenance %6d B: %lu us avg\r\n", len, avg / 100);
    }
}

void lab4_part3(void)   /* HPC0 behind CCI: plain C, zero cache calls */
{
    fill_fir_input(tx, BUF_BYTES);
    dma_fir_once(tx, rx, BUF_BYTES);
    int rc = memcmp(rx, golden_fir_output(), BUF_BYTES);
    xil_printf("HPC0, zero cache calls: %s\r\n", rc ? "FAIL" : "PASS");
}
