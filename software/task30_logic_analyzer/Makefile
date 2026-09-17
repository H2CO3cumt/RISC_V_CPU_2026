ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
AUTOSTART ?= 0
OBJCOPY := $(RISCV_PREFIX)objcopy
OBJDUMP := $(RISCV_PREFIX)objdump
READELF := $(RISCV_PREFIX)readelf
BUILD := build
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra -DTASK30_AUTOSTART=$(AUTOSTART)
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/task30_logic_analyzer.map
.PHONY: all clean check-isa
all: $(BUILD)/task30_logic_analyzer.elf $(BUILD)/task30_logic_analyzer.dis $(BUILD)/task30_logic_analyzer.mem $(BUILD)/task30_logic_analyzer.attributes check-isa
$(BUILD):
	@mkdir -p $(BUILD)
$(BUILD)/task30_logic_analyzer.elf: start.S task30_logic_analyzer.c link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S task30_logic_analyzer.c -lgcc
$(BUILD)/task30_logic_analyzer.mem: $(BUILD)/task30_logic_analyzer.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
$(BUILD)/task30_logic_analyzer.dis: $(BUILD)/task30_logic_analyzer.elf
	$(OBJDUMP) -d -M no-aliases $< > $@
$(BUILD)/task30_logic_analyzer.attributes: $(BUILD)/task30_logic_analyzer.elf
	$(READELF) -A $< > $@
clean:
	rm -rf $(BUILD)
check-isa: $(BUILD)/task30_logic_analyzer.dis $(BUILD)/task30_logic_analyzer.attributes
	@pwsh -NoProfile -File ../../scripts/check_coremark_elf.ps1 -Disassembly $(BUILD)/task30_logic_analyzer.dis -Attributes $(BUILD)/task30_logic_analyzer.attributes
