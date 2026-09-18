ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
BUILD := build
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld
.PHONY: all clean
all: $(BUILD)/gpio_only.mem
$(BUILD):
	@mkdir -p $(BUILD)
$(BUILD)/gpio_only.elf: gpio_only.c start.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ gpio_only.c start.S
$(BUILD)/gpio_only.mem: $(BUILD)/gpio_only.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
clean:
	rm -rf $(BUILD)
