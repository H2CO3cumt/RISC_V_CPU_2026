ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
AUTOSTART ?= 0
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
READELF := $(RISCV_PREFIX)readelf
BUILD := build
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra -DLOGIC_ANALYZER_AUTOSTART=$(AUTOSTART)
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/logic_analyzer.map
.PHONY: all clean check-isa
all: $(BUILD)/logic_analyzer.elf $(BUILD)/logic_analyzer.dis $(BUILD)/logic_analyzer.mem $(BUILD)/logic_analyzer.attributes check-isa
$(BUILD):
	@mkdir -p $(BUILD)
$(BUILD)/logic_analyzer.elf: start.S logic_analyzer.c link.ld | $(BUILD)
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
	@pwsh -NoProfile -File ../../scripts/check_coremark_elf.ps1 -Disassembly $(BUILD)/logic_analyzer.dis -Attributes $(BUILD)/logic_analyzer.attributes
