# Project Progress

> 最后更新：2026-08-29  
> 状态依据：`AGENTS.md`、`docs/competition_scoring.md`、`docs/roadmap.md`、`docs/architecture.md`、`docs/interfaces.md`、`docs/application_logic_analyzer.md` 与当前项目文件。聊天记录不作为任务完成证明。

## 当前阶段

Task 2 - RV32I 指令格式

## 已完成

- [x] 项目基线与核心文档建立
- [x] 赛题需求分析
- [x] CPU 基础概念
- [x] 按 2026 紫光同创 RISC-V 赛题重新校准任务顺序和 Gate
- [x] 确立 CPU Core / SoC 外设解耦原则并建立 `docs/interfaces.md` 接口契约
- [x] 选定“可重构多协议逻辑分析仪”应用并建立功能、MMIO、验证和量化指标规格
- [x] 固定报名作品名称“RISC-V多协议逻辑分析仪”和410字符作品简介
- [x] 根据官方赛题页建立 `docs/competition_scoring.md`，明确基础、性能、应用、文档和高阶任务映射
- [x] 重新冻结单人 60 天国赛冲刺范围：基础项和官方性能指标全保留，应用固定 8 通道 Raw P0 闭环，RLE 与 BTB 本届不启动并移至赛后研究
- [x] 在项目根目录初始化本地 Git 仓库，默认分支为 `main`，并建立首版 `.gitignore`
- [x] 从本届路线删除Cache/burst、完整异常中断、AI、DDR/HDMI/PCIe/千兆网、自定义指令及逻辑分析仪扩展项
- [ ] RV32I 指令格式
- [ ] GCC 工具链
- [ ] Register File
- [ ] ALU

## 当前工具与平台状态

- 仿真器：Icarus Verilog 14.0 (devel)，可用。
- RISC-V GCC：xPack GNU RISC-V Embedded GCC 15.2.0，安装于 `D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1`；前缀为 `riscv-none-elf-`，`RISCV_PREFIX` 与 PATH 已配置。
- RISC-V 工具链验证：使用 `-march=rv32i -mabi=ilp32` 成功完成 C 编译、链接、反汇编以及 BIN/IHEX 生成；输出为 ELF32 little-endian RISC-V，`rv32i/ilp32/libgcc.a` 存在。
- GNU Make：xPack Windows Build Tools 4.4.1，安装于 `D:\Tools\xpack-windows-build-tools-4.4.1-3`，已通过实际 Makefile 构建验证。
- PDS：2024.2-SP2-EN，安装于 `D:\Pango\PDS_2024.2-SP2`；`pds_shell -version` 验证通过，PATH 已配置。目标器件/BRAM 工程冒烟验证仍按 Task 10 执行。
- Python/串口：Python 3.13.15 位于 `D:\Python313`；pySerial 3.5 位于 `D:\Python313\Lib\site-packages`，导入和串口枚举验证通过。
- Python D 盘约束：`PYTHONUSERBASE=D:\PythonUser`、`PIP_CACHE_DIR=D:\PythonCache\pip`，后续用户包与缓存固定到 D 盘。
- 目标 FPGA/开发板：尚未记录具体型号；D3 前必须确定实体板卡或远程 FPGA 平台，Task 10 再完成器件、时钟/Reset 和 BRAM 冒烟验收。
- 固定编译目标：`-march=rv32i -mabi=ilp32`。
- 详细工具版本、路径、校验值和验证结果见 `docs/toolchain.md`。

## 当前稳定 RTL

暂无。

## 当前 Regression

暂无。

## 当前已知问题

- 目标紫光同创 FPGA/开发板型号尚未确定；不阻塞当前 Task 2 学习，但必须在 D3 前形成平台决策，否则国赛冲刺硬节点 FAIL，并继续阻塞 Task 10 通过。
- 逻辑分析仪物理引脚和最高采样目标依赖 Task 10 的开发板确认；本届通道数已固定为8，系统时钟 clock-enable 方案不阻塞当前任务。
- Git 仓库已建立，首次基线提交与 GitHub 私有远程状态见本次 Git 配置结果。

## 国赛冲刺基线

- 冲刺基准日：`D0 = 2026-08-29`；内部目标日：`D60 = 2026-10-28`。若官方截止更早，以官方截止为准。
- 本届唯一交付主线：Task 0～30、33～35；Task 31 RLE 与 Task 32 BTB 固定跳过，不进入本届 RTL、Regression、bitstream 或材料。
- 硬节点：D3 硬件平台决策、D12 单周期候选 Reference、D20 `single_cycle_stable`、D35 Pipeline/GCC/性能计数器、D42 `pipeline_coremark_stable`、D52 逻辑分析仪 P0、D60 `competition_final`。
- 国赛证据链固定为：正确性（指令/Regression/提交级对比）、性能（CoreMark/MHz、Fmax、CoreMark/LUT、CPI）、应用（8 通道 Raw UART/SPI 闭环）、工程质量（Core/SoC 解耦、可复现构建、报告/视频/答辩）。
- 提前完成产生的时间只用于 Regression、Timing/CoreMark 复现、P0 稳定性和参赛材料，不恢复已冻结功能。

## 下一目标

主线目标：学习并能够正确拆解 RV32I 的 R、I、S、B、U、J 六类指令格式；完成每类至少一个拆解练习，正确解释 immediate 重排与符号扩展，并通过 Task 2 验收。

并行的非 RTL 硬截止：在 D3 前确定目标板卡/器件、PDS 工程路径、时钟/Reset 和 BRAM 冒烟验证方案；该决策不得跳过 Task 2～9 的学习与模块 Gate。

## 更新规则

每完成一个任务，必须同步更新本文件：

1. 将通过验收的任务标记为 `[x]`，未通过的任务保持 `[ ]`。
2. 将“当前阶段”推进到下一个任务；不得跳过 `docs/roadmap.md` 的前置任务和 Gate。
3. 在“当前稳定 RTL”中列出已经通过相关 Regression 的稳定文件。
4. 在“当前 Regression”中记录测试名称和 `PASS` / `FAIL`；失败时不得标记任务完成。
5. 在“当前已知问题”中记录尚未解决的问题；重要 Bug 同时写入 `docs/debug_log.md`。
6. 将“下一目标”写成当前任务的具体验收目标。
7. 更新顶部日期，并确保记录与当前代码和实际测试结果一致。
