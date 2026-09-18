# RISC-V CPU 最终交付说明

更新时间：2026-09-17。仓库 `D:\RISC_V_CPU_2026` 是权威开发状态，`release/final_submission` 是唯一最终交付目录。

## 唯一最终版本

- 顶层：`mes50hp_logic_analyzer_top`
- 器件与时钟：PGL50H-6IFBG484，50 MHz
- 内容：RV32I 五级流水线、16 项直接映射 BTB、UART/GPIO、十项性能计数器、八通道 Raw 逻辑分析仪
- 下载文件：`release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit`
- SHA-256：`2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`
- 时序：All Constraints Met，setup WNS +2.661 ns，hold WHS +0.312 ns，估算 Fmax 57.6735 MHz
- 资源：3459 LUT、3129 FF、5.5 个 DRM18K 等效块

开发阶段的 Pipeline、CoreMark 和 DebugCore 配置仅保留为历史验证证据，不是交付入口，也不需要用户选择。

## J8 接线

只需八根杜邦线连接隔行相邻脚对：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。奇数脚为激励输出，偶数脚为采集输入。

## 验证状态

RTL、GCC、官方 CoreMark CRC、Predictor Off/On、逻辑分析仪、Python/VCD 和最终 PDS 均已通过。最终位流已由 JTAG 下载到 PGL50H（DONE=1），J8 static/counter/UART/SPI 四模式各连续 20 次，共 80/80 实体回环 PASS；证据位于 `release/evidence/logic_analyzer_board_final`。

`release/final_submission`、`release/artifacts` 与 `fpga/logic_analyzer/generate_bitstream` 的位流 SHA-256 必须一致（`2C09E690…4746E`），位流、时序、约束、固件与实体回环证据必须来自同一次最终构建；任何源文件修改后都要重新执行 `export_final_submission.ps1`、`create_release_manifest.ps1` 和 `audit_release_package.ps1`。发布脚本需用 PowerShell 7 执行（本机为 Codex 运行时 `pwsh.exe`），不能用 Windows PowerShell 5.1。

## 参赛材料

- `release/materials/technical_report.docx` / `.pdf`：13 页技术报告（含当前限制与后续工作）。
- `release/materials/defense_presentation.pptx`、`defense_qa.md`、`video_script.md`、`field_recovery_card.md`：答辩 PPT、问答稿、三分钟视频脚本和现场恢复卡。
- `release/evidence/automated_metrics.md` / `.json`：自动提取的资源、时序与 Predictor Before/After 指标。

实体板 CoreMark 分数、Task 29 Fabric Debugger 波形与三轮断电压力仍未采集，因此当前发布标识保持 `competition_final_candidate`。
