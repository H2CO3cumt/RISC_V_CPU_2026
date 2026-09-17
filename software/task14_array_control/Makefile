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
LDFLAGS := -nostdlib -nostartfiles -Wl,-T,link.ld -Wl,-Map,$(BUILD)/task14_array_control.map

.PHONY: all clean check-isa

all: $(BUILD)/task14_array_control.elf $(BUILD)/task14_array_control.dis $(BUILD)/task14_array_control_imem.mem $(BUILD)/task14_array_control_dmem.mem check-isa

$(BUILD):
	@mkdir -p $(BUILD)

$(BUILD)/task14_array_control.elf: task14_array_control.c start.S link.ld | $(BUILD)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ task14_array_control.c start.S

$(BUILD)/task14_array_control.dis: $(BUILD)/task14_array_control.elf
	$(OBJDUMP) -d -S -M no-aliases $< > $@

$(BUILD)/task14_array_control_imem.mem: $(BUILD)/task14_array_control.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --only-section=.text $< $@

$(BUILD)/task14_array_control_dmem.mem: $(BUILD)/task14_array_control.elf
	$(OBJCOPY) -O verilog --verilog-data-width=4 --only-section=.data $< $@

check-isa: $(BUILD)/task14_array_control.dis
	@cmd /c "findstr /I /C:\"mul\" /C:\"div\" /C:\"rem\" /C:\"c.\" /C:\"fadd\" /C:\"fsub\" $(BUILD)\\task14_array_control.dis >nul && (echo TASK14 ISA CHECK FAIL: unsupported extension instruction found & exit /b 1) || (echo TASK14 ISA CHECK PASS: RV32I-only disassembly & exit /b 0)"

clean:
	rm -rf $(BUILD)
