/* MES50HP bare-metal CoreMark port.  The benchmark sources remain the
 * unmodified EEMBC checkout under third_party/coremark. */
#ifndef CORE_PORTME_H
#define CORE_PORTME_H

#define HAS_FLOAT 0
#define HAS_TIME_H 0
#define USE_CLOCK 0
#define HAS_STDIO 0
#define HAS_PRINTF 0

#define COMPILER_VERSION "GCC " __VERSION__
/* 实际使用的 -march 由 Makefile 经 -DCOREMARK_MARCH 传入（默认 rv32i，
   即赛题与项目固定的基线口径）。CoreMark 会把这一行打印到串口，因此
   RV32I 基线与 RV32IM 增强镜像的输出能自证各自用的是哪套 ISA，
   引用分数时不会把两个批次混在一起。 */
#ifndef COREMARK_MARCH
#define COREMARK_MARCH "rv32i"
#endif
/* 优化等级必须**如实自证**：CoreMark 报告规则要求写明编译选项。
   这一行以前写死 "-O2"，一旦用别的优化等级构建，串口自证行就会说谎。
   现在由 Makefile 用 -DCOREMARK_OPT_STR=... 传入实际使用的优化选项，
   未传入时退回 "-O2"，保证与历史镜像逐字节可比。 */
#ifndef COREMARK_OPT_STR
#define COREMARK_OPT_STR "-O2"
#endif
#define COMPILER_FLAGS COREMARK_OPT_STR " -march=" COREMARK_MARCH " -mabi=ilp32"
#define MEM_LOCATION "STATIC BRAM"

typedef signed short ee_s16;
typedef unsigned short ee_u16;
typedef signed int ee_s32;
typedef double ee_f32;
typedef unsigned char ee_u8;
typedef unsigned int ee_u32;
typedef ee_u32 ee_ptr_int;
typedef ee_u32 ee_size_t;

#ifndef NULL
#define NULL ((void *)0)
#endif
#define align_mem(x) (void *)(4 + (((ee_ptr_int)(x) - 1) & ~3))

#define CORETIMETYPE ee_u32
typedef ee_u32 CORE_TICKS;

#define SEED_METHOD SEED_VOLATILE
#define MEM_METHOD MEM_STATIC
#define MULTITHREAD 1
#define USE_PTHREAD 0
#define USE_FORK 0
#define USE_SOCKET 0
#define MAIN_HAS_NOARGC 1
#define MAIN_HAS_NORETURN 0

extern ee_u32 default_num_contexts;
typedef struct CORE_PORTABLE_S { ee_u8 portable_id; } core_portable;

void portable_init(core_portable *p, int *argc, char *argv[]);
void portable_fini(core_portable *p);
int ee_printf(const char *fmt, ...);
void uart_send_char(char ch);

#endif
