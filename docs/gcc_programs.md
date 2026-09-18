# Task 14 GCC Bare-Metal Programs

> 状态：PASS（2026-09-12）。Task 14 功能验收已完成；本文件记录其构建、加载约定与验证证据。

## 固定构建约定

- 工具前缀只取用户环境变量 `RISCV_PREFIX`；当前工程不硬编码其他前缀。
- 编译参数固定为 `-march=rv32i -mabi=ilp32 -O1`，并使用 `-ffreestanding`、`-fno-builtin`、`-fno-stack-protector`、`-fno-pic`、`-fno-pie`、`-msmall-data-limit=0`。
- 链接时使用 `-nostdlib -nostartfiles`；当前程序没有 `libgcc` 依赖，也没有乘除法。
- 每次构建生成带机器码的反汇编，并自动拒绝 `M`、`C`、浮点等未支持扩展指令。

## 当前加载约定

现阶段单周期 CPU 内部仍有独立的 `imem` 与 `dmem` 阵列。测试平台将 `.text` 镜像加载到 IMEM；对于含初值的 `.data` 程序，测试平台在解除 Reset 前将 `.data` 镜像加载到 DMEM。同一地址值在两个阵列中分别表示指令地址与数据地址，这是 Task 14 当前内部存储模型的约定，不是 Task 15 的冻结 Core/SoC 事务接口。

启动代码将 `sp` 设为 `0x400`：当前 256-word DMEM 的最高合法字节地址为 `0x3FC`，首个函数栈帧向下分配后位于有效范围内。

## 已验证程序

| 程序 | 覆盖点 | 自动断言 |
|---|---|---|
| `software/c_smoke` | 启动栈、`.bss` 清零、函数调用/返回、循环、全局 Store | `result = 45`，即 `DMEM[128] = 45`；复位前的垃圾值必须先被启动代码清零 |
| `software/c_array_control` | `.data` 预加载、`.bss` 清零、局部数组、函数调用、两段循环、`if/else` 的真/假分支 | `seed = 3`，`result = 18`，`false_result = -1`，即 `DMEM[128] = 3`、`DMEM[129] = 18`、`DMEM[130] = 0xFFFF_FFFF`；两个 `.bss` word 均先被清零 |

运行：

```powershell
.\scripts\run_c_program_regression.ps1
```

## 后续 Gate 的工作（不阻塞 Task 14 PASS）

- 为 `.data`/`.bss` 形成面向后续 Core/SoC 边界的正式加载契约。
- 更多数组边界与软件运行库路径验证。
- 将全部 Task 14 程序纳入候选 Reference 的提交级 trace 比较。
- 曾观察到一次 `rv32ui-p-srai` 超时；单项指令级调试与随后完整核心套件中的该用例均在约 220 周期 PASS，当前未复现。Task 14 未修改 RTL。
