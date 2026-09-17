ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif

COREMARK_ROOT ?= ../../third_party/coremark
ITERATIONS ?= 1000
CLOCK_HZ ?= 50000000
AUTOSTART ?= 0
CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
READELF := $(RISCV_PREFIX)readelf
SIZE    := $(RISCV_PREFIX)size
BUILD   := build

CORE_SRCS := $(COREMARK_ROOT)/core_list_join.c $(COREMARK_ROOT)/core_main.c \
             $(COREMARK_ROOT)/core_matrix.c $(COREMARK_ROOT)/core_state.c \
             $(COREMARK_ROOT)/core_util.c
CFLAGS := -march=rv32i -mabi=ilp32 -O2 -ffreestanding -fno-builtin \
          -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 \
          -mstrict-align -ffunction-sections -fdata-sections -Wall -Wextra \
          -I. -I$(COREMARK_ROOT) -DITERATIONS=$(ITERATIONS) \
          -DCOREMARK_CLOCK_HZ=$(CLOCK_HZ) -DCOREMARK_AUTOSTART=$(AUTOSTART) \
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

check-isa: $(BUILD)/coremark.dis $(BUILD)/coremark.attributes
	@pwsh -NoProfile -File ../../scripts/check_coremark_elf.ps1 -Disassembly $(BUILD)/coremark.dis -Attributes $(BUILD)/coremark.attributes

clean:
	rm -rf $(BUILD)
