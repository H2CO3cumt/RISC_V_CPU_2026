ifndef RISCV_PREFIX
$(error RISCV_PREFIX is not set; for this project use riscv-none-elf-)
endif

CC      := $(RISCV_PREFIX)gcc
OBJDUMP := $(RISCV_PREFIX)objdump
OBJCOPY := $(RISCV_PREFIX)objcopy
BUILD   := build

CFLAGS  := -march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin \
           -fno-stack-protector -fno-pic -fno-pie -msmall-data-limit=0 \
           -Wall -Wextra
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/c_smoke_sum.map

.PHONY: all clean check-isa

all: $(BUILD)/c_smoke_sum.elf $(BUILD)/c_smoke_sum.dis $(BUILD)/c_smoke_sum.mem check-isa

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/c_smoke_sum.elf: c_smoke_sum.c start.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ c_smoke_sum.c start.S

$(BUILD)/c_smoke_sum.dis: $(BUILD)/c_smoke_sum.elf
	$(OBJDUMP) -d -S -M no-aliases $< > $@

$(BUILD)/c_smoke_sum.mem: $(BUILD)/c_smoke_sum.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 $< $@

check-isa: $(BUILD)/c_smoke_sum.dis
	@cmd /c "findstr /I /C:\"mul\" /C:\"div\" /C:\"rem\" /C:\"c.\" /C:\"fadd\" /C:\"fsub\" $(BUILD)\\c_smoke_sum.dis >nul && (echo C PROGRAM ISA CHECK FAIL: unsupported extension instruction found & exit /b 1) || (echo C PROGRAM ISA CHECK PASS: RV32I-only disassembly & exit /b 0)"

clean:
	rm -rf $(BUILD)
