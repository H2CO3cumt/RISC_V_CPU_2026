// Project-local target shell for the upstream riscv-tests rv32ui sources.
// It deliberately uses only RV32I instructions supported by the current Core.

#ifndef RISC_V_CPU_2026_RISCV_TEST_H
#define RISC_V_CPU_2026_RISCV_TEST_H

#define RVTEST_RV32U \
  .macro init; \
  .endm

#define RVTEST_RV64U RVTEST_RV32U

#define RVTEST_CODE_BEGIN \
  .section .text.init; \
  .align 2; \
  .globl _start; \
_start:

#define RVTEST_CODE_END

#define TESTNUM gp

// A nonzero word at tohost ends the test: 1 is PASS; other values are FAIL.
#define RVTEST_PASS \
  fence; \
  li TESTNUM, 1; \
  la t0, tohost; \
  sw TESTNUM, 0(t0); \
1: j 1b

#define RVTEST_FAIL \
  fence; \
1: beqz TESTNUM, 1b; \
  sll TESTNUM, TESTNUM, 1; \
  ori TESTNUM, TESTNUM, 1; \
  la t0, tohost; \
  sw TESTNUM, 0(t0); \
2: j 2b

#define RVTEST_DATA_BEGIN \
  .pushsection .tohost,"aw",@progbits; \
  .align 2; .global tohost; tohost: .word 0; .size tohost, 4; \
  .popsection; \
  .align 4; .global begin_signature; begin_signature:

#define RVTEST_DATA_END \
  .align 4; .global end_signature; end_signature:

#endif
