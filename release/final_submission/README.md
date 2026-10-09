# MES50HP RISC-V 多协议逻辑分析仪最终版

唯一下载文件：`bitstream/mes50hp_riscv_logic_analyzer.sbit`（**85 MHz 版**）。
已验证备用文件：`bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit`（50 MHz 版，仅在主位流异常时使用）。

PDS 工程文件（**两个，都可以在 PDS 2024.2-SP2 里直接打开、查看源码/约束并下载或重建**）：

- `MES50HP_RISCV_Logic_Analyzer.pds` —— **逻辑分析仪应用**（交付主位流，85 MHz）。重建配方 `build_pds.tcl`。
- `MES50HP_CoreMark_85M.pds` —— **CoreMark 跑分**（85 MHz）。重建配方 `build_coremark_pds.tcl`。
  打开后 Top 是 `mes50hp_coremark_pll_top`；CPU/SoC 源码与逻辑分析仪工程共用 `rtl/`，
  跑分专用源文件是 `rtl/coremark_program_memory.v` + `rtl/mes50hp_coremark_pll_top.v` + `rtl/coremark_*.mem`，
  约束是 `constraints/mes50hp_coremark_85m.fdc`。

**看波形（不需要装任何软件）**：双击包根目录 `波形预览.html`，浏览器里就是**本交付位流在实体板上实测抓到**的
四种模式波形（static / counter / uart / spi，标签切换、滚轮缩放、红色虚线是触发点）。
它同时也是通用查看器：把任意 .vcd 拖进去即可显示。

**接板子自己跑一遍（同样零依赖）**：下载**主位流** `bitstream/mes50hp_riscv_logic_analyzer.sbit`（**85 MHz**），
按 J8 相邻脚对接好 8 根杜邦线（3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32），
然后**双击包根目录 `采集四模式.cmd`**：它用 Windows 自带的 PowerShell 与 .NET 串口完成四模式采集，
不需要安装 Python；跑完自动打开输出目录，双击里面的 `波形预览.html` 或 `<模式>\<模式>_00.html` 看波形。
（包内仍保留 Python 图形界面上位机 `启动逻辑分析仪.cmd`：**窗口里自带实时波形面板**，
勾「实时连续采集」就能边采边看，实测约 1.3 次/秒；装了 Python 就可以用这条更直观的路径。
完整说明与手动串口协议见 `逻辑分析仪使用说明.md`。）
（`bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit` 是**已验证备用位流**，只在主位流异常时切换使用。）

**CoreMark 跑分复现**：本包自带跑分专用位流 `bitstream/mes50hp_coremark_85m.sbit`、
**可直接打开的跑分 PDS 工程** `MES50HP_CoreMark_85M.pds`、EEMBC 官方 CoreMark 源码、跑分固件工程、
实际烧进 FPGA 的存储器镜像、上位机脚本与金标准输出，
**不依赖任何开发工作区**即可自己跑出分数并核对官方 CRC。
**跑分只需双击包根目录 `跑分.cmd`**（Windows 自带功能，不需要装 Python；跑完自动打开
`results\coremark\`，双击里面的 `跑分结果.html` 就能看分数与逐项金标准核对）。
**一页说明见 `coremark/跑分复现说明.md`**（期望结果：85 MHz 下 **Score 79.587**、
CoreMark/MHz **0.936**、官方 CRC **PASS**、运行 31.412 s）。

- 器件：PGL50H-6IFBG484；板载晶振 50 MHz，经片上 PLL 倍频到 **85 MHz** 供 CPU/SoC 使用
  （`pll_85m`：50 MHz / IDIV 1 = PFD 50 MHz，× FDIV 17 = VCO 850 MHz，/ ODIV0 10 = **85.000 MHz** 精确整数频率）。
  PDS 推导的生成时钟见 `reports/timing.rtr`：请求 85.0000 MHz、估算 **90.0766 MHz**、slack **+0.663 ns**、**All Constraints Met**。
- CPU：RV32I 五级流水线，16 项直接映射 BTB，2-bit 饱和计数器；机器模式 CSR/Trap/MRET（mstatus/mie/mtvec/mepc/mcause/mtval/mip 等）与三根设备无关中断输入。
- 外设：片上 RAM、CP2102 UART、GPIO、性能计数器、8 通道 Raw 逻辑分析仪、机器定时器（mtime/mtimecmp，窗口 0x1000_3000，聚合出定时器中断）。
- J8 回环：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
- 时序：All Constraints Met；慢角 setup WNS +0.663 ns，hold WHS +0.304 ns，估算 Fmax 90.0766 MHz。
- 综合资源：4814 LUT、3858 FF、5.5 个 DRM18K 等效块。
- bitstream SHA-256：788F1CEB273FA626DF4581FD46B65A2D90761D9A2B393D35FCEE0C111622DCE2。

自动 RTL/软件/PDS 回归均已通过（scripts\run_final_regression.ps1 → ALL AUTOMATED FINAL REGRESSION PASS）。

**实体板证据（2026-09-29 实测，当时对应 50 MHz 位流 `BCAE040A…`）：**

- 位流下载：scripts\program_board.ps1 -Config la50 与 -Config cm50 均为 PROGRAM PASS，done bit is 1；
  （**当前交付主位流是 85 MHz 版**，下载请用 -Config la85；la50 现在是已验证备用配置）
- J8 四模式实板验收：scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 →
  LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80（static/counter/uart/spi 各 20/20；各模式单次返回样本数 static 5、counter 5、uart 236、spi 85，触发位置依次 0/0/15/4；作品自带逻辑分析仪的 Raw 缓存深度为 256 样本，与 PDS DebugCore 探针的 512 样本不是一回事）；
- CoreMark 实板复现：scripts\run_coremark_board.ps1 -Port COM11 →
  COREMARK BOARD PASS clock_hz=50000000 ticks=1068006999 seconds=21.360 score_x1000=46816
  （运行 21.36 秒，满足赛题"不少于 10 秒"）；
- **板级裸机中断（2026-09-30 完成）**：`fpga/timer_demo` 最小板级工程，
  `python python\timer_demo_board.py --port COM11 --seconds 6` → 捕获 12 次周期性中断，
  计数序列 `890123456789`、LED 序列 `010101010101`；固件用 mtime 自计时，中断周期中位数
  **12,517,376 拍 = 250.348 ms**（预期 250.0 ms）。证据 `release/evidence/timer_demo_board/`。
  ⚠️ 此项用的是 `fpga/timer_demo` **独立演示位流**（`5E58B421…`），不是本包的逻辑分析仪位流。
- **ILA 抓 Trap 进入/返回（2026-09-30 完成，M-24 收口）**：`fpga/timer_demo_ila` 工程，192 位探针 × 512 样本。
  抓取 A（触发 `ila_event_trap`）trap@256 / return@251；抓取 B（触发 `ila_event_trap_return`）return@256 / trap@261。
  两次互为正/反向触发，`event_trap` 与 `event_trap_return` 各产生**恰好一个**脉冲，`irq_timer` 全程为 1，
  illegal/misaligned/bus_error 全程为 0。证据 `fpga/timer_demo_ila/evidence/`（位流 `452EE532…`）。
  由此 `docs/trap_contract.md` 的 **M-24 收口为 PASS**，矩阵 M-01…M-24 全部 PASS。
- **CoreMark 关键循环 ILA 波形（2026-09-30 完成）**：证据 `release/evidence/ila_coremark/`。
- **80 MHz PLL 板级 CoreMark（2026-09-30 首次按当前批次实测）**：位流 `F0743756…`，
  `ticks=2670014377`、2500 迭代、**33.375 s**、Score **74.905**、CoreMark/MHz **0.936**、CRC **PASS**。
  证据 `release/evidence/coremark_board_cm80_20260930.json`。
- **S1 DDR3 板级证据已独立落盘并复现（2026-09-30）**：`S1 DDR3 SMOKE BOARD PASS`（BIST err_cnt 全程 0），
  证据 `release/evidence/ddr3_smoke_board/`（位流 `FAEDF476…`）。
- **交付位流为 85 MHz 版，并已做稳定性 soak（2026-09-30）**：
  本包主位流工作在 85 MHz，J8 四模式 **80/80 PASS**，证据 `evidence/logic_analyzer_board_final/`。
  50 MHz 版位流作为**已验证备用**一并提供（对应 `docs/roadmap.md` 任务 35「主版本失败时能切换已验证备用版本」）。

**读数纪律（引用板级数字前必读）**：

1. CoreMark 分数来自 **CoreMark 专用位流**（50 MHz `DC95F9D0…` / 80 MHz `F0743756…` /
   85 MHz `751C692B…` / 90 MHz `664CD28C…`），**不是**本包的逻辑分析仪位流。
2. 板级 **CPI 有窗口敏感性**：同一颗位流实测过 1.494 与 1.508，而 `ticks`/Score/`flushes` 逐位相同。
   ⇒ **CPI 只能写 ≈1.50，不能写 1.508 这种四位精度**；Score/ticks 可照写。
3. `run_coremark_board.ps1` 无条件把 `clock_hz` 写成 50 MHz，跑 80 MHz 位流时它打印的 `seconds`
   是错的（真实 33.375 s，不是 53.400 s）。

**已知未做（如实标注，不是"已完成"也不是"不适用"）**：

- **三轮断电一致性**：`run01` 只做了"重新下载（Reset 等价）"，**没有真的断过电**；
  `run02`/`run03` 未做，**因为用户 2026-09-30 明确表示不做**（见 `release/evidence/board/README.md`）。
- 80 MHz 逻辑分析仪回环（只有 50 MHz 有 80/80）；
- DDR3 **未接入 CPU 存储路径**，也没有任何 DDR3 吞吐/延迟数字；
- N4 的 89.25 MHz 候选位流**从未上板**。

**全部数字的出处见 `release/evidence/claims_map.md`**（数字 ↔ 证据文件 ↔ 位流哈希对照表，含未宣称清单）。
再按 `逻辑分析仪使用说明.md` 跑 J8 四模式；CoreMark 用 `scripts\run_coremark_board.ps1 -Port COM11`。