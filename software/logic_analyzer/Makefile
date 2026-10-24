ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
AUTOSTART ?= 0
# 镜像容量档位（2026-10-24 新增，默认 4 KB 即原样）：
#   RAM_KB 为空 → link.ld（4 KB）：交付工程的固件就在这里，编译结果逐字节不变；
#   RAM_KB=8    → link8k.ld（8 KB）+ -DRAM_KB=8（start.S 的 sp 跟着抬到 0x2000）。
# 只有 tr85 那档演示位流需要 8 KB：它的组合命令 0xAB 在 4 KB 里装不下（溢出 436 B）。
# 三处必须同时一致：RAM_KB、LINKER_SCRIPT、以及 fpga/*/rtl 里存储器模块的 DEPTH。
RAM_KB ?=
LINKER_SCRIPT ?= link.ld
EXTRA_CFLAGS :=
ifneq ($(RAM_KB),)
EXTRA_CFLAGS := -DRAM_KB=$(RAM_KB)
endif
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
READELF := $(RISCV_PREFIX)readelf
BUILD := build
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra -DLOGIC_ANALYZER_AUTOSTART=$(AUTOSTART) $(EXTRA_CFLAGS)
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,$(LINKER_SCRIPT) -Wl,-Map,$(BUILD)/logic_analyzer.map
.PHONY: all clean check-isa
all: $(BUILD)/logic_analyzer.elf $(BUILD)/logic_analyzer.dis $(BUILD)/logic_analyzer.mem $(BUILD)/logic_analyzer.attributes check-isa
$(BUILD):
	@mkdir -p $(BUILD)
$(BUILD)/logic_analyzer.elf: start.S logic_analyzer.c $(LINKER_SCRIPT) | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S logic_analyzer.c -lgcc
$(BUILD)/logic_analyzer.mem: $(BUILD)/logic_analyzer.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
$(BUILD)/logic_analyzer.dis: $(BUILD)/logic_analyzer.elf
	$(OBJDUMP) -d -M no-aliases $< > $@
$(BUILD)/logic_analyzer.attributes: $(BUILD)/logic_analyzer.elf
	$(READELF) -A $< > $@
clean:
	rm -rf $(BUILD)
check-isa: $(BUILD)/logic_analyzer.dis $(BUILD)/logic_analyzer.attributes
	@sh ../../scripts/run_check_coremark_elf.sh -Disassembly $(BUILD)/logic_analyzer.dis -Attributes $(BUILD)/logic_analyzer.attributes
