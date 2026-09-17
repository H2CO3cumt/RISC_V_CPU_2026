# 复现与现场验收说明

本文给出从干净目录重建比赛配置、核对证据和连接 MES50HP 的唯一流程。所有命令从仓库根目录运行。脚本默认使用 Icarus 12、`riscv-none-elf-` 和 `D:\Pango\PDS_2024.2-SP2`，也允许用 `IVERILOG_ROOT`、`RISCV_PREFIX`、`PDS_ROOT` 和 `PANGO_LICENSE_FILE` 覆盖。

## 一键构建

完整自动化构建包括 RV32I、Reference、Pipeline/Hazard、GCC、性能计数器、官方 CoreMark fixed/random、三种 SoC、逻辑分析仪、Python/VCD、范围审计和四份 PDS bitstream：

```powershell
./scripts/build_competition_release.ps1 -LicenseFile 'D:\Downloads\new_pds_60452e195a32.lic'
```

仅复用已经生成的 PDS 文件时：

```powershell
./scripts/build_competition_release.ps1 -SkipPds
```

失败时 `tmp/final_regression_summary.txt` 保留最后通过项和第一个失败入口。成功后 `release/artifacts` 只保留唯一最终配置的位流、时序报告与正式固件镜像（`mes50hp_riscv_logic_analyzer.sbit`、`mes50hp_riscv_logic_analyzer_timing.rtr`、`logic_analyzer_firmware.mem`），`release/SHA256SUMS.txt` 覆盖源码和交付物。开发阶段的 Pipeline、CoreMark 与 DebugCore bitstream 只留在各自 `fpga/*/generate_bitstream/` 目录作为历史证据，不进入下载入口；这些 PDS 实现阶段目录不纳入 Git，需用 PDS 重建。

## 正式配置与诊断配置

交付只使用一套配置：`release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit`，与 `release/artifacts/mes50hp_riscv_logic_analyzer.sbit` 及 `fpga/task30_logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit` 的 SHA-256 必须一致（当前 `2C09E690…4746E`）。该配置上电输出 `LA_READY`，等待 13 字节带 XOR 校验的配置包，可切换 static、counter、UART 8N1 与 SPI mode 0，无需重新综合。

开发阶段的三套配置保留在 `fpga/task26_pipeline_soc`、`fpga/task28_coremark` 和 `fpga/task29_coremark_ila`，只作为历史验证证据与 ILA 调试入口，不属于交付下载项，也不需要使用者选择。`coremark_ila` 的 192-bit、512-sample 探针只用于 Task 29 波形证据，不参与正式资源或 Fmax 计分。

器件必须显示 `PGL50H-6IFBG484`。系统时钟为 50 MHz，默认使用内部上电复位。`REST` 只用于重新加载配置，不接 CPU Core。CP2102 串口固定为 115200、8N1、无流控，FPGA RX=`R8`、TX=`R9`。

## 直接上板验证工程包

若只需把工程交给板卡验证人员，使用 `release/board_validation`：该目录自包含四个 PDS 工程、共享 RTL、约束、Task 29 DebugCore IP、四份可下载 `.sbit`、PDS recipe，以及 `pyui/pyUI.py` 图形验证界面。该目录含 PDS 实现数据库，不纳入 Git，分发形式是 `release/MES50HP_board_validation_package.zip`；解压回 `release/board_validation` 后可用 `./scripts/audit_board_validation_package.ps1` 校验，保持目录层级不变后可直接打开：

```text
release/board_validation/projects/task26_pipeline_soc/impl.pds
release/board_validation/projects/task28_coremark/task28_generated.pds
release/board_validation/projects/task29_coremark_ila/task29_coremark_ila.pds
release/board_validation/projects/task30_logic_analyzer/task30_generated.pds
```

先用 PDS Programmer 下载 `release/board_validation/bitstreams/*.sbit`，再运行 `python release/board_validation/pyui/pyUI.py`。PyUI 通过 CP2102 执行 CoreMark UART 和逻辑分析仪 static/counter/UART/SPI 四模式，并保存原始日志、JSON 和 VCD；无图形环境时可直接调用同目录的 `coremark_serial.py` 与 `logic_analyzer_serial.py`。首次使用仅需安装 `pyserial`：`python -m pip install -r release/board_validation/pyui/pyUI_requirements.txt`。

## CoreMark 实体证据

在 PDS Programmer 中下载 `coremark_stable.sbit`，连接独立 CP2102 USB 数据线并确认其 COM 号，然后运行：

```powershell
./scripts/run_coremark_board.ps1 -Port COM5
```

脚本发送 `R`、等待不超过 70 秒、校验三个官方 CRC、`Correct operation validated`、迭代数、计时不少于 10 秒和七项性能计数器，并写入 `release/evidence/coremark_uart.log` 与 `coremark_board.json`。若任一字段缺失，脚本退出非零，不生成 PASS。

## CoreMark DebugCore 实体证据

下载 `coremark_debug_ila.sbit`，在 Fabric Debugger 中选择 `coremark_ila`。探针宽度为 192 bit、深度为 512 samples、采样时钟为 50 MHz；字段表以 `fpga/task29_coremark_ila/README.md` 为准。可用 bit 0 触发退休事件，或用 bit 174/176 观察 Branch/Flush。该诊断构建的 PDS 结果为 4416 LUT、4458 FF、39 DRM、setup WNS +5.453 ns、hold WNS +0.186 ns，50 MHz 约束通过；这些数字只描述诊断配置，正式性能与资源指标仍取 `coremark_stable.sbit`。

## 逻辑分析仪实体回环

断电后共地，用 8 根杜邦线在 J8 上逐位短接相邻的输出/输入脚：

| 通道 | J8 输出 | J8 输入 | FPGA 输出管脚 | FPGA 输入管脚 |
|---:|---|---|---|---|
| 0 | J8 3 | J8 4 | AB13 | Y13 |
| 1 | J8 7 | J8 8 | W11 | V11 |
| 2 | J8 11 | J8 12 | Y10 | W10 |
| 3 | J8 15 | J8 16 | Y12 | W12 |
| 4 | J8 19 | J8 20 | U10 | T10 |
| 5 | J8 23 | J8 24 | V9 | U9 |
| 6 | J8 27 | J8 28 | W8 | V7 |
| 7 | J8 31 | J8 32 | Y6 | W6 |

下载 `logic_analyzer_p0.sbit` 后运行四种无需重新综合的模式：

```powershell
./scripts/run_task30_board.ps1 -Port COM5
```

脚本依次执行 static、counter、UART 与 SPI，每种 20 次；每次等待 `LA_READY`，发送带 XOR 校验配置，验证 count/trigger，UART/SPI 模式还验证解析字节，然后保存 80 份 UART log、VCD 和总 JSON。任何超时、校验失败、解码错误或样本位置错误都会立即停止。

## Reset 与断电重复

正式验收依次执行三轮：断电五秒，重新供电，下载同一 SHA-256 bitstream，运行对应实体脚本。每轮把串口输出保存到 `release/evidence/board/run01`、`run02`、`run03`。逻辑分析仪每轮应完成 80 次采集，CoreMark 每轮应输出相同 CRC、iterations 和 ticks。板卡未连接时这些目录必须保持为空，报告不得使用 RTL 仿真替代实体结果。

## 指标与材料

`./scripts/run_release_evidence.ps1` 从 PDS 报告和官方 CoreMark RTL 日志生成 `release/evidence/automated_metrics.json` 与 Markdown 表：资源三元组统一取综合统计（LUT 3459、寄存器 3129、DRM18K 5.5），布局布线后的实现 FF（3120）单独记为 `ff_implemented`，两个阶段不得混用。技术报告、答辩 PPT、视频脚本和故障恢复卡位于 `release/materials`。所有材料使用 `release/build_manifest.txt` 中同一组 hash；RTL 或软件发生任何变化后必须重跑完整构建并重建清单。

发布脚本必须用 PowerShell 7 执行：`export_final_submission.ps1`、`create_release_manifest.ps1` 和 `audit_release_package.ps1` 使用 .NET Core 的 `System.IO.Path.GetRelativePath`，在 Windows PowerShell 5.1 下还会因 GBK 解码损坏中文文件名。`scripts/generate_defense_deck.mjs` 依赖 Codex 运行时的 `@oai/artifact-tool`，只能在原环境重新生成 PPTX；成品已随 `release/materials` 交付，不需要重新生成。
