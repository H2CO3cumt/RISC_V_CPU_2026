ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif

CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
READELF := $(RISCV_PREFIX)readelf

BUILD   := build
CFLAGS  := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin \
           -fno-stack-protector -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/hello.map

.PHONY: all clean check-isa

all: $(BUILD)/hello.elf $(BUILD)/hello.dis $(BUILD)/hello.bin $(BUILD)/hello.hex $(BUILD)/hello.mem check-isa

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/hello.elf: hello.c start.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ hello.c start.S

$(BUILD)/hello.dis: $(BUILD)/hello.elf
	$(OBJDUMP) -d -S -M no-aliases $< > $@

$(BUILD)/hello.bin: $(BUILD)/hello.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/hello.hex: $(BUILD)/hello.elf
	$(OBJCOPY) -O ihex $< $@

$(BUILD)/hello.mem: $(BUILD)/hello.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

check-isa: $(BUILD)/hello.dis
	@cmd /c "findstr /I /C:\"mul\" /C:\"div\" /C:\"rem\" /C:\"c.\" /C:\"fadd\" /C:\"fsub\" $(BUILD)\\hello.dis >nul && (echo HELLO UART ISA CHECK FAIL: unsupported extension instruction found & exit /b 1) || (echo HELLO UART ISA CHECK PASS: RV32I-only disassembly & exit /b 0)"

clean:
	rm -rf $(BUILD)
