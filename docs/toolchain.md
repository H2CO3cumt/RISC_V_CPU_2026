# Toolchain and Development Environment

> 最后验证：2026-08-28  
> 安装约束：所有可选择位置的项目软件、Python 包和缓存均放在 D 盘。

## 1. 已安装工具

| 工具 | 版本 | 安装位置 | 状态 |
|---|---|---|---|
| xPack GNU RISC-V Embedded GCC | 15.2.0 | `D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1` | PASS |
| GNU Make / xPack Windows Build Tools | 4.4.1 | `D:\Tools\xpack-windows-build-tools-4.4.1-3` | PASS |
| Pango Design Suite | 2024.2-SP2-EN | `D:\Pango\PDS_2024.2-SP2` | PASS（程序启动与版本检查） |
| Icarus Verilog / VVP | 14.0 development | `D:\oss-cad-suite\bin` | PASS |
| GTKWave | OSS CAD Suite | `D:\oss-cad-suite\bin` | 已安装 |
| Verilator / Yosys / OpenOCD | OSS CAD Suite | `D:\oss-cad-suite\bin` | 已安装 |
| Git | 2.55.0.windows.3 | `D:\Git` | PASS |
| Python | 3.13.15 | `D:\Python313` | PASS |
| pySerial | 3.5 | `D:\Python313\Lib\site-packages` | PASS |

PDS 的目标器件、约束、BRAM 初始化与下载器验证属于 Task 10，不能仅凭程序能启动就提前宣称该 Gate 通过。

## 2. 用户环境变量

```text
RISCV_TOOLCHAIN=D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1
RISCV_PREFIX=riscv-none-elf-
PYTHONUSERBASE=D:\PythonUser
PIP_CACHE_DIR=D:\PythonCache\pip
XPACKS_STORE_FOLDER=D:\Tools\xPacks
```

用户 PATH 已包含以下 D 盘目录：

```text
D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1\bin
D:\Tools\xpack-windows-build-tools-4.4.1-3\bin
D:\Pango\PDS_2024.2-SP2\bin
D:\oss-cad-suite\bin
D:\Git\cmd
D:\Python313
D:\Python313\Scripts
D:\PythonUser\Python313\Scripts
```

构建脚本统一使用 `$(RISCV_PREFIX)gcc`、`$(RISCV_PREFIX)objdump`、`$(RISCV_PREFIX)objcopy`，不得假设可执行文件一定使用 `riscv32-unknown-elf-` 或 `riscv64-unknown-elf-` 前缀。

## 3. 官方安装包与完整性

RISC-V GCC 来源：

```text
https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v15.2.0-1/xpack-riscv-none-elf-gcc-15.2.0-1-win32-x64.zip
SHA-256: 85EF714DACD273B1DADF4AF4892774520AC01915BFA6DA816A56E7E41591E09E
```

GNU Make 来源：

```text
https://github.com/xpack-dev-tools/windows-build-tools-xpack/releases/download/v4.4.1-3/xpack-windows-build-tools-4.4.1-3-win32-x64.zip
SHA-256: 113D4DFDBBC56DC9B865C9F75D38CD0DA82F0D7094187E6F7A803FE6EEF1D218
```

两个压缩包均在解压前完成 SHA-256 校验，结果与官方 manifest 一致。

## 4. RV32I 实际验证结果

验证程序使用：

```text
-march=rv32i -mabi=ilp32 -O1 -ffreestanding -fno-builtin -nostdlib -nostartfiles
```

自动构建成功生成：

- ELF 可执行文件。
- `objdump` 反汇编。
- Binary 镜像。
- Intel HEX 镜像。

`readelf` 结果：

```text
Class: ELF32
Data: 2's complement, little endian
Machine: RISC-V
```

反汇编只出现 RV32I 指令，包括 `lui`、`lw`、`add`、`sw`、`jal`，未混入 `M` 或 `C` 扩展。`-march=rv32i -mabi=ilp32 -print-libgcc-file-name` 指向存在的 `rv32i/ilp32/libgcc.a`。

## 5. 其他验证

- `make --version`：GNU Make 4.4.1。
- `pds_shell -version`：2024.2-SP2-EN。
- `import serial`：pySerial 3.5，从 `D:\Python313\Lib\site-packages` 加载。
- 串口枚举：执行成功，当前检测到 6 个 COM 端口。
- C 盘误装的 pySerial 副本已精确删除；普通导入与禁用 user-site 导入均使用 D 盘版本。
