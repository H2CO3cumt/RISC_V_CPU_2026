ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif

COREMARK_ROOT ?= ../../third_party/coremark
ITERATIONS ?= 1000
CLOCK_HZ ?= 50000000
AUTOSTART ?= 0
# ISA 基线：默认 rv32i（赛题与项目冻结口径，历史全部成绩都来自它）。
# 传 MARCH=rv32im 可以用同一份源码构建 M 扩展镜像，用来给出
# "RV32I 基线 vs RV32IM" 的 Before/After。两个镜像必须分别留档，
# 引用分数时必须写明用的是哪一个（docs/competition_scoring.md §2）。
MARCH ?= rv32i
# 输出目录：换 ISA 时用 BUILD=build_im，避免覆盖已登记哈希的 rv32i 镜像。
BUILD ?= build
# 置 1 时在 start_time() 里清零性能计数器，使七项计数器与 CoreMark 计时窗口同口径。
# 这是观测口径开关，不改变被测量的执行路径；默认关闭以保持与历史镜像逐字节可比。
PERF_WINDOW_ALIGN ?= 0
# 优化等级。默认 -O2 是历史全部成绩的口径，**不得静默改动**：
# 换优化等级属于"口径变更"，必须在报告与 claims_map 里把
# -O2 与 -O3 两个点并列留档，引用分数时写明优化等级。
# 传 COREMARK_OPT='-O3 -funroll-all-loops -finline-functions' 可构建高优化镜像。
COREMARK_OPT ?= -O2
empty :=
space := $(empty) $(empty)
# ???????????,????**??** argv ?? gcc,
# ?? make ??????????(??? unrecognized option)?
COREMARK_OPT_ESC := $(subst $(space),\$(space),$(COREMARK_OPT))
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
READELF := $(RISCV_PREFIX)readelf
SIZE    := $(RISCV_PREFIX)size

CORE_SRCS := $(COREMARK_ROOT)/core_list_join.c $(COREMARK_ROOT)/core_main.c \
             $(COREMARK_ROOT)/core_matrix.c $(COREMARK_ROOT)/core_state.c \
             $(COREMARK_ROOT)/core_util.c
CFLAGS := -march=$(MARCH) -mabi=ilp32 $(COREMARK_OPT) -ffreestanding -fno-builtin \
          -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 \
          -mstrict-align -ffunction-sections -fdata-sections -Wall -Wextra \
          -I. -I$(COREMARK_ROOT) -DITERATIONS=$(ITERATIONS) \
          -DCOREMARK_CLOCK_HZ=$(CLOCK_HZ) -DCOREMARK_AUTOSTART=$(AUTOSTART) \
          -DCOREMARK_MARCH=\"$(MARCH)\" \
          -DCOREMARK_OPT_STR=\"$(COREMARK_OPT_ESC)\" \
          -DPERF_WINDOW_ALIGN=$(PERF_WINDOW_ALIGN) \
          -DPERFORMANCE_RUN=1
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,--gc-sections \
           -Wl,-Map,$(BUILD)/coremark.map

.PHONY: all clean check-isa
all: $(BUILD)/coremark.elf $(BUILD)/coremark.dis $(BUILD)/coremark_imem.mem \
     $(BUILD)/coremark_dmem.mem $(BUILD)/coremark.attributes \
     $(BUILD)/coremark.size check-isa

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/coremark.elf: start.S core_portme.c core_portme.h ee_printf.c link.ld $(CORE_SRCS) | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S core_portme.c ee_printf.c $(CORE_SRCS) -lgcc

$(BUILD)/coremark.dis: $(BUILD)/coremark.elf
	$(OBJDUMP) -d -S -M no-aliases $< > $@

$(BUILD)/coremark_imem.mem: $(BUILD)/coremark.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --only-section=.text $< $@

$(BUILD)/coremark_dmem.mem: $(BUILD)/coremark.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --only-section=.rodata --only-section=.data $< $@

$(BUILD)/coremark.attributes: $(BUILD)/coremark.elf
	$(READELF) -A $< > $@

$(BUILD)/coremark.size: $(BUILD)/coremark.elf
	$(SIZE) -A -x $< > $@

# ISA 校验按 MARCH 双向收口：rv32i 镜像必须"一条 M 指令都没有"，
# rv32im 镜像必须"真的有 M 指令且 ELF 属性是 rv32im2p1"。
# 只查一个方向不够：镜像被换错时，另一侧的校验会静默通过。
EXPECT_ARCH := $(if $(filter rv32im,$(MARCH)),rv32im2p1,rv32i2p1)

check-isa: $(BUILD)/coremark.dis $(BUILD)/coremark.attributes
	@sh ../../scripts/run_check_coremark_elf.sh -Disassembly $(BUILD)/coremark.dis -Attributes $(BUILD)/coremark.attributes -ExpectArch $(EXPECT_ARCH)

clean:
	rm -rf $(BUILD)
