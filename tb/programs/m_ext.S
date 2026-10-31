/* M 扩展（RV32IM）端到端验收程序。
 *
 * 用途：同一份镜像同时喂给五级流水 CPU 和单周期 Reference CPU，
 * 由 tb/tb_pipeline_m_ext.v 逐条比较提交 trace、x1~x31 与数据 RAM。
 *
 * 覆盖点（每一条都对应 tb_mdu.v 里已用手算值验证过的语义）：
 *   1. mul/mulh/mulhsu/mulhu 四条乘法在正数、负数、溢出边界上的取值；
 *   2. div/divu/rem/remu 四条除法的四种符号组合；
 *   3. 除零（商 -1、余数 = 被除数）与 -2^31 / -1 溢出；
 *   4. RAW 冒险：乘除法结果被紧跟其后的指令立刻使用（不插 NOP），
 *      专门验证 M 结果的转发与"除法停顿期间前端停住"；
 *   5. 循环里带乘法（贴近 CoreMark 矩阵那种用法）+ 结果写回内存，
 *      用数据 RAM 的最终内容交叉验证写回值。
 *
 * 汇编方式见 scripts/run_pipeline_m_ext_tb.ps1，必须用 -march=rv32im。
 */
    .section .text
    .globl _start
_start:
    addi x1, x0, 20          /* x1  = 20 */
    addi x2, x0, 6           /* x2  = 6  */

    mul    x3, x1, x2        /* x3  = 120            (0x00000078) */
    mulh   x4, x1, x2        /* x4  = 0              (high(120)) */
    mulhsu x5, x1, x2        /* x5  = 0 */
    mulhu  x6, x1, x2        /* x6  = 0 */
    div    x7, x1, x2        /* x7  = 3 */
    rem    x8, x1, x2        /* x8  = 2 */
    divu   x9, x1, x2        /* x9  = 3 */
    remu   x10, x1, x2       /* x10 = 2 */

    addi x11, x0, -20        /* x11 = -20            (0xFFFFFFEC) */
    mul    x12, x11, x2      /* x12 = -120           (0xFFFFFF88) */
    mulh   x13, x11, x2      /* x13 = 0xFFFFFFFF     (high(-120)) */
    div    x14, x11, x2      /* x14 = -3             (0xFFFFFFFD) */
    rem    x15, x11, x2      /* x15 = -2             (0xFFFFFFFE) */
    divu   x16, x11, x2      /* x16 = 0x2AAAAAA7     (4294967276 / 6) */
    remu   x17, x11, x2      /* x17 = 2 */

    div    x18, x1, x0       /* x18 = 0xFFFFFFFF     (除以 0) */
    rem    x19, x1, x0       /* x19 = 20             (除以 0 的余数 = 被除数) */

    lui    x20, 0x80000      /* x20 = 0x80000000 */
    addi   x21, x0, -1       /* x21 = 0xFFFFFFFF */
    div    x22, x20, x21     /* x22 = 0x80000000     (溢出: -2^31 / -1) */
    rem    x23, x20, x21     /* x23 = 0              (溢出余数) */

    /* RAW：乘除法结果被下一条指令立刻使用，中间不插 NOP */
    mul    x24, x3, x2       /* x24 = 720            (0x000002D0) */
    add    x25, x24, x1      /* x25 = 740            (0x000002E4) */
    div    x26, x25, x2      /* x26 = 123            (0x0000007B) */
    add    x27, x26, x0      /* x27 = 123 */

    sw     x3, 0(x0)         /* RAM[0] = 120 */
    sw     x7, 4(x0)         /* RAM[1] = 3   */
    sw     x14, 8(x0)        /* RAM[2] = 0xFFFFFFFD */
    sw     x22, 12(x0)       /* RAM[3] = 0x80000000 */

    addi x28, x0, 0          /* 累加器 */
    addi x29, x0, 5          /* 循环计数 */
loop:
    add  x28, x28, x1        /* acc += 20 */
    mul  x30, x28, x2        /* 循环体内乘法：acc * 6 */
    addi x29, x29, -1
    bne  x29, x0, loop

    sw   x28, 16(x0)         /* RAM[4] = 100 (0x64) */
    sw   x30, 20(x0)         /* RAM[5] = 600 (0x258) */
done:
    jal  x0, done            /* 自跳转：两个 CPU 都停在这里，便于比较最终状态 */
