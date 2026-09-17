ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif

CC := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
BUILD := build
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld

.PHONY: all clean
all: $(BUILD)/task16_mmio_demo.elf $(BUILD)/task16_mmio_demo.dis $(BUILD)/task16_mmio_demo.mem
$(BUILD):
	@mkdir -p $(BUILD)
$(BUILD)/task16_mmio_demo.elf: task16_mmio_demo.c start.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ task16_mmio_demo.c start.S
$(BUILD)/task16_mmio_demo.dis: $(BUILD)/task16_mmio_demo.elf
	$(OBJDUMP) -d -S -M no-aliases $< > $@
$(BUILD)/task16_mmio_demo.mem: $(BUILD)/task16_mmio_demo.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
clean:
	rm -rf $(BUILD)
