ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; set it to riscv-none-elf-)
endif
CC := $(RISCV_PREFIX)gcc
OBJCOPY := $(RISCV_PREFIX)objcopy
CFLAGS := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 -Wall -Wextra -DFINAL_AUTOSTART=0
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,firmware.map
all: firmware.elf firmware.mem
firmware.elf: start.S logic_analyzer_firmware.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ start.S logic_analyzer_firmware.c -lgcc
firmware.mem: firmware.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@
clean:
	rm -f firmware.elf firmware.mem firmware.map
