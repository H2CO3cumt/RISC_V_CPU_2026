# TASK3：C 到 RV32I 机器码

在此目录执行 `make`，构建脚本从环境变量 `RISCV_PREFIX` 取得工具前缀。

生成物：

- `build/hello.elf`：包含段、入口和符号等元数据的 ELF 文件。
- `build/hello.dis`：带机器码的可读反汇编。
- `build/hello.bin`：纯二进制镜像。
- `build/hello.hex`：Intel HEX 镜像。
- `build/hello.mem`：Verilog 风格初始化文件；其地址单位和字节序必须由未来 IMEM wrapper 明确约定后再直接使用。

本例故意包含：函数调用与返回（`jal`/`jalr`）、循环分支、寄存器加法、全局变量的 Load/Store，以及裸机无限循环。
