ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
BUILD := build

# 与项目其它软件目录一致：-march=rv32i -mabi=ilp32（AGENTS.md §1.7）。
# 注意这条 march 不含 zicsr，所以 start.S 里的 CSR 指令是 .word 编码写的。
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra

# DELTA 由 scripts/generate_timer_demo_fpga_memory.ps1 显式传入（交付=12500000，仿真=200000）。
# 没有 TEST_DELTA 之类的开关：**数值只有一个来源**，避免"传了 -Delta 却被别处的常量覆盖"
# 这类事故（本文件早先的 TEST_DELTA=2000 分支就真的覆盖过调用方传进来的值）。
ifneq ($(DELTA),)
CFLAGS += -DMTIMECMP_DELTA=$(DELTA)
endif
# 诊断用的额外宏，由生成脚本的 -ExtraDefine 原样透传（交付构建为空）。
ifneq ($(EXTRA_DEFINE),)
CFLAGS += $(EXTRA_DEFINE)
endif

LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/timer_demo.map

.PHONY: all clean
all: $(BUILD)/timer_demo.elf $(BUILD)/timer_demo.dis $(BUILD)/timer_demo.mem

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/timer_demo.elf: start.S timer_demo_config.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S

$(BUILD)/timer_demo.mem: $(BUILD)/timer_demo.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

# 反汇编是**独立于生成脚本**的核对手段：.word 写的 CSR 指令会原样显示成
# `.word 0x...`，可以用 `objdump -d -M no-aliases -M zicsr` 之外的位域反解核对。
$(BUILD)/timer_demo.dis: $(BUILD)/timer_demo.elf
	$(OBJDUMP) -d -M no-aliases $< > $@

clean:
	rm -rf $(BUILD)
