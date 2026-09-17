#include "coremark.h"
#include "core_portme.h"

#ifndef ITERATIONS
#define ITERATIONS 1000
#endif
#ifndef COREMARK_CLOCK_HZ
#define COREMARK_CLOCK_HZ 50000000u
#endif

#define UART_TXDATA (*(volatile ee_u32 *)0x10000000u)
#define UART_STATUS (*(volatile ee_u32 *)0x10000004u)
#define UART_RXDATA (*(volatile ee_u32 *)0x10000008u)
#define GPIO_OUTPUT (*(volatile ee_u32 *)0x10001000u)
#define PERF_BASE ((volatile ee_u32 *)0x10002000u)

volatile ee_s32 seed1_volatile = 0;
volatile ee_s32 seed2_volatile = 0;
volatile ee_s32 seed3_volatile = 0x66;
volatile ee_s32 seed4_volatile = ITERATIONS;
volatile ee_s32 seed5_volatile = 0;
ee_u32 default_num_contexts = 1;

static CORETIMETYPE start_time_val;
static CORETIMETYPE stop_time_val;

static ee_u32 read_counter_low(ee_u32 word_offset)
{
    return PERF_BASE[word_offset];
}

void uart_send_char(char ch)
{
    while ((UART_STATUS & 1u) == 0u) { }
    UART_TXDATA = (ee_u32)(ee_u8)ch;
}

CORETIMETYPE barebones_clock(void)
{
    /* A formal CoreMark run is kept below the 32-bit wrap interval
     * (85.9 s at 50 MHz), so the low word gives exact elapsed cycles. */
    return read_counter_low(0u);
}

void start_time(void) { start_time_val = barebones_clock(); }
void stop_time(void) { stop_time_val = barebones_clock(); }
CORE_TICKS get_time(void) { return stop_time_val - start_time_val; }
secs_ret time_in_secs(CORE_TICKS ticks)
{
    return ticks / (ee_u32)COREMARK_CLOCK_HZ;
}

void portable_init(core_portable *p, int *argc, char *argv[])
{
    (void)argc;
    (void)argv;
    if (sizeof(ee_ptr_int) != sizeof(ee_u8 *))
        ee_printf("ERROR! ee_ptr_int cannot hold a pointer\r\n");
    if (sizeof(ee_u32) != 4)
        ee_printf("ERROR! ee_u32 is not 32 bits\r\n");
#if !COREMARK_AUTOSTART
    /* 正式板级镜像由上位机显式启动，避免 JTAG 下载后串口尚未打开而
     * 丢失唯一一份结果。等待时间位于 start_time() 之前，不计入成绩。 */
    ee_printf("COREMARK_READY: send R to start\r\n");
    while (1) {
        if ((UART_STATUS & 4u) != 0u) {
            ee_u32 command = UART_RXDATA & 0xffu;
            if (command == (ee_u32)'R' || command == (ee_u32)'r')
                break;
        }
    }
    ee_printf("COREMARK_START\r\n");
#endif
    p->portable_id = 1;
}

void portable_fini(core_portable *p)
{
    CORE_TICKS ticks = get_time();
    ee_u32 score_x1000 = 0;
    ee_u32 score_per_mhz_x1000 = 0;
    if (ticks != 0u) {
        unsigned long long numerator =
            (unsigned long long)(ee_u32)ITERATIONS * (ee_u32)COREMARK_CLOCK_HZ;
        score_x1000 = (ee_u32)((numerator * 1000ull) / ticks);
        score_per_mhz_x1000 = (ee_u32)(
            ((unsigned long long)(ee_u32)ITERATIONS * 1000000000ull) / ticks);
    }
    ee_printf("CoreMark score x1000 : %u\r\n", score_x1000);
    ee_printf("CoreMark/MHz x1000  : %u\r\n", score_per_mhz_x1000);
    ee_printf("PERF cycle=%08x instret=%08x stall=%08x load=%08x branch=%08x taken=%08x flush=%08x\r\n",
              read_counter_low(0u), read_counter_low(2u),
              read_counter_low(4u), read_counter_low(6u),
              read_counter_low(8u), read_counter_low(10u),
              read_counter_low(12u));
    ee_printf("COREMARK_DONE\r\n");
    GPIO_OUTPUT = 0xC3u;
    p->portable_id = 0;
}
