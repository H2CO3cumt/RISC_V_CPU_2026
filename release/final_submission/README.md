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
**五种模式**波形（static / counter / uart / spi / **mirror**，标签切换、滚轮缩放、红色虚线是触发点；
其中 mirror 页就是"上位机发一句 `HELLO,RISC-V`、逻辑分析仪把它抓下来"的那张图）。
它同时也是通用查看器：把任意 .vcd 拖进去即可显示。

**接板子自己跑一遍（同样零依赖）**：下载**主位流** `bitstream/mes50hp_riscv_logic_analyzer.sbit`（**85 MHz**），
按 J8 相邻脚对接好 8 根杜邦线（3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32），
然后**双击包根目录 `采集四模式.cmd`**：它用 Windows 自带的 PowerShell 与 .NET 串口完成四模式采集，
不需要安装 Python；跑完自动打开输出目录，双击里面的 `波形预览.html` 或 `<模式>\<模式>_00.html` 看波形。
想连**镜像 / 字符串**那一路一起抓（就是上面 mirror 页），在包根目录用自带 PowerShell 跑：
`tools\logic_analyzer_capture.ps1 -Output results -Runs 1 -Modes static,counter,uart,spi,mirror`
（字符串默认 `HELLO,RISC-V`，可用 `-MirrorText` 改；J8-31↔32 那对线必须接好）。
（包内仍保留 Python 图形界面上位机 `启动逻辑分析仪.cmd`：**窗口里自带实时波形面板**，
勾「实时连续采集」就能边采边看，实测约 1.3 次/秒；装了 Python 就可以用这条更直观的路径。
完整说明与手动串口协议见 `逻辑分析仪使用说明.md`。）

**单文件功能展示上位机（包根目录 `逻辑分析仪演示.py`，2026-10-10 新增）**：装了 Python + pyserial 后
`py 逻辑分析仪演示.py` 直接运行，**五种功能都在这一个文件里**：
static / counter / uart / spi 四种回环模式，加 **mirror 镜像抓取**（板级 ch7 镜像 `uart0_rx`，
发一句 `HELLO,RISC-V` 就能抓到**它自己发出去的真实串口波形**，2048 点、8 采样点/比特、UART 解码 0 错误）；
界面右栏是**仪器读数**（每通道频率/周期/占空比/脉宽/边沿数、帧数与帧错误、推算波特率），
可导出 VCD / 网页波形页 / Markdown 测量报告，另有 `--selftest` 自检。
它是目前功能最全的上位机；`启动逻辑分析仪.cmd` 会自动找到 `tools\pyUI.py`（仓库与交付包通用），
并停在第 ① 页「八通道波形」真采集页，两条路径并存。
**第 ② 页「CPU 数据流（寄存器热力图）」不需要开发板也能看**：双击包根目录 `离线演示.cmd`，
它回放 `tools/samples/trace_hello_rv.log`（2026-10-24 实体板真实回包：100 条记录 / 8 个打点），
页面顶部会显示 **「离线回放」徽标**——那是录像、不是板子此刻采到的数据，判据仅供参考；
接上板子并用 `启动逻辑分析仪.cmd` 采一枪，徽标才会消失。
（`bitstream/mes50hp_riscv_logic_analyzer_50m_fallback.sbit` 是**已验证备用位流**，只在主位流异常时切换使用。）

**CoreMark 跑分复现**：本包自带跑分专用位流 `bitstream/mes50hp_coremark_85m.sbit`（RV32I，Score 79.587）、
**RV32IM（M 扩展）同频位流** `bitstream/mes50hp_coremark_im_85m.sbit`（Score **193.192**、CoreMark/MHz **2.272**）、
**可直接打开的跑分 PDS 工程** `MES50HP_CoreMark_85M.pds`、EEMBC 官方 CoreMark 源码、跑分固件工程、
实际烧进 FPGA 的存储器镜像（RV32I 在 `images/`、RV32IM 在 `images/rv32im/`）、
重建配方（`rebuild/` 与 `rebuild_rv32im/`）、上位机脚本与两份金标准输出
（`expected/coremark_expected_output.txt`、`expected/coremark_expected_output_rv32im.txt`），
**不依赖任何开发工作区**即可自己跑出分数并核对官方 CRC。
> 两颗位流**同一个工程、同一个 85 MHz 时钟，差别只有程序镜像的 `-march`**；
> 这就是"M 扩展把 CoreMark/MHz 从 0.936 提到 2.272"的完整、可自证的复现路径。
**跑分只需双击包根目录 `跑分.cmd`**（Windows 自带功能，不需要装 Python；跑完自动打开
`results\coremark\`，双击里面的 `跑分结果.html` 就能看分数与逐项金标准核对）。
**一页说明见 `coremark/跑分复现说明.md`**（期望结果：85 MHz 下 **Score 79.587**、
CoreMark/MHz **0.936**、官方 CRC **PASS**、运行 31.412 s）。

- 器件：PGL50H-6IFBG484；板载晶振 50 MHz，经片上 PLL 倍频到 **85 MHz** 供 CPU/SoC 使用
  （`pll_85m`：50 MHz / IDIV 1 = PFD 50 MHz，× FDIV 17 = VCO 850 MHz，/ ODIV0 10 = **85.000 MHz** 精确整数频率）。
  PDS 推导的生成时钟见 `reports/timing.rtr`：请求 85.0000 MHz、估算 **90.0766 MHz**、slack **+0.663 ns**、**All Constraints Met**。
- CPU：RV32I 五级流水线，16 项直接映射 BTB，2-bit 饱和计数器；机器模式 CSR/Trap/MRET（mstatus/mie/mtvec/mepc/mcause/mtval/mip 等）与三根设备无关中断输入。
- 外设：片上 RAM、CP2102 UART、GPIO、性能计数器、8 通道 Raw 逻辑分析仪（采集深度 **2048** 点；
  ch7 可切换为**镜像 `uart0_rx`**，用来抓上位机自己发出去的串口波形）、机器定时器（`mtime`/`mtimecmp`，窗口 0x1000_3000，聚合出定时器中断）。
- J8 回环：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
- 时序：All Constraints Met；慢角 setup WNS +0.577 ns，hold WHS +0.308 ns，估算 Fmax 89.3841 MHz。
- 综合资源：4995 LUT、3908 FF、6.0 个 DRM18K 等效块。
- bitstream SHA-256：C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F。

自动 RTL/软件/PDS 回归均已通过（scripts\run_final_regression.ps1 → ALL AUTOMATED FINAL REGRESSION PASS）。

**实体板证据（当前交付位流，2026-10-10 实测，85 MHz 版 `8908FD8C…`）：**

- **五模式实板验收（含 mirror）**：`scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` →
  **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`**（static / counter / uart / spi / **mirror** 各 20/20）。
  mirror 每次返回 **2048** 个采样点，解码出 `HELLO,RISC-V`（`48454C4C4F2C524953432D56`）、帧错误 0。
  证据目录 `evidence/logic_analyzer_board_final/`（含每次采集的 .vcd / .html / summary.json）。
  这次复测是在**移除仪器面板之后**做的，用来证明"拆掉面板没有破坏原通路"。

**实体板证据（2026-09-29 历史记录，当时对应 50 MHz 位流 `BCAE040A…`、四模式、深度 256）：**

- 位流下载：scripts\program_board.ps1 -Config la50 与 -Config cm50 均为 PROGRAM PASS，done bit is 1；
  （**当前交付主位流是 85 MHz 版**，下载请用 -Config la85；la50 现在是已验证备用配置）
- J8 四模式实板验收（**当时**，未含 mirror）：scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 →
  LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=80（static/counter/uart/spi 各 20/20；各模式单次返回样本数 static 5、counter 5、uart 236、spi 85，触发位置依次 0/0/15/4；作品自带逻辑分析仪的 Raw 缓存深度**当时为 256 样本**，现已提升到 **2048**，与 PDS DebugCore 探针的 512 样本不是一回事）；
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
  本包主位流工作在 85 MHz，四模式累计 **320 次采集零失败**（首次验收 80 次 + 3 轮 soak × 80 次），
  原始证据在开发仓库 `release/evidence/logic_analyzer_board_85m/` 与 `logic_analyzer_board_85m_soak/`。
  **本包内** `evidence/logic_analyzer_board_final/` 放的是 **2026-10-10 的最新一次复测**
  （五模式含 mirror、**100/100 PASS**，见上方"当前交付位流"）。
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