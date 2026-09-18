# Debug Log

> 最后更新：2026-09-17（CPI 优化专项）

本文件只记录已经实际发生、对架构或后续开发有复用价值的重要 Bug。尚未开始 RTL 时不预填虚构问题。

## 记录格式

每个 Bug 使用以下字段：

- 日期与任务。
- 失败测试和最小复现程序。
- 第一个错误周期。
- 第一个错误信号。
- 预期值与实际值。
- 根因。
- 最小修复范围。
- 修复后的验证命令与 Regression 结果。
- 是否影响 Reference Model、接口或架构文档。

### 2026-09-17 / 交付冻结：改名暴露出的 4 个既有脆弱点

一次性把 `taskNN_*` 命名改成功能化命名（`fpga/coremark`、`fpga/logic_analyzer`、`fpga/coremark_ila`、
`scripts/run_*`、`tb/tb_*`、`tb/data/*.mem`、`software/*` 等）。改名本身不改行为，但暴露并修掉了 4 个既有问题：

1. **测试依赖仓库里的陈旧固件产物**：`run_soc_harness_tb.ps1` 直接读 `software/<prog>/build/<prog>.mem`，
   自己不做 `make`。旧产物一直存在所以从没暴露；固件改名后立刻报 `$readmemh: Unable to open …`。
   修复：runner 增加 `make -C software/mmio_demo all`，测试自包含。
2. **发布审计把位流哈希写死**：`audit_release_package.ps1` 里 `$expected='2C09E690…'`，任何一次重新综合后
   审计必然失败，无法跟随新位流。修复：以 `fpga/logic_analyzer/generate_bitstream/…sbit` 为唯一真实来源，
   要求 `final_submission` 与 `release/artifacts` 两处副本与之逐字节一致。
3. **审计依赖 `rg`**：本机 PATH 无 ripgrep 时审计在命名检查处中断（不是「没发现问题」，而是命令失败）。
   修复：优先用 `rg`，缺失时回退到 PowerShell `Select-String`，保留「交付包不得出现 taskNN」这条检查。
4. **导出脚本整目录删除**：`Remove-Item -Recurse` 遇到被 PDS GUI 占用的 `.pds.lock` 时中途失败，
   留下**半成品发布包**（本次实际发生）。修复：改为逐项删除、跳过被占用条目并告警；
   `.lock` 本来就被清单与审计按设计排除。

证据：修复后 `run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`；
`FINAL SUBMISSION EXPORT PASS files=206`、`RELEASE MANIFEST PASS files=1963`、`RELEASE PACKAGE AUDIT PASS final_files=126 artifacts=3`。

### 2026-09-17 / 工具：Fabric Debugger 无 GUI 抓 ILA 波形的可行流程

- 背景：赛题要求「利用 ILA 抓取的波形图分析 CoreMark 关键算法的流水线效率」，此前只有诊断位流、没有实体波形。
- 结论：`cdt_dbg.exe -file <tcl>` 提供了完整 CLI，**不需要打开 GUI**。可用命令（来自
  `Fabric_Debugger_User_Guide.pdf`）：`dbg_connect / dbg_scan_chain / dbg_program / dbg_import_fic /
  dbg_fla_get_bus / dbg_fla_run / dbg_fla_trig_immd / dbg_fla_export_wf_data / dbg_disconnect / dbg_close`。
- 踩坑记录：
  1. **必须先下载匹配的位流再 `dbg_import_fic`**，否则报 `Debugger-4001: FIC file isn't matching`。
  2. `dbg_fla_power_init` 在本设计上失败（`get_power_on_init_data exec unsuccessfully`）。它是可选项：
     IP 未开「power-on init data」时必然失败，但**不影响抓取**。TCL 脚本里若保留它，会因为
     “命令失败即中断后续命令”而整段停在导出之前——要么去掉，要么在其后加 `clean`。
  3. `dbg_fla_set_capture -type N -samples 512` 报 `Capture type or arguments is illegal`；
     直接用 IP 默认抓取配置即可（本设计为单窗口 512 拍）。
  4. `open_cable` 偶尔耗时 5 分钟以上（USB 重新枚举）。**同一时刻只能有一个进程占用下载线**：
     前一次中断的 `cdt_dbg` 不退出会一直占线，导致后续进程卡在 `open_cable`/`dbg_scan_chain`。
     排查方法：`Get-CimInstance Win32_Process -Filter "Name like 'cdt%'"` 看有几个客户端。
  5. CoreMark 镜像 `AUTOSTART=0` 会等串口 `R`：抓取期间需要另起一个持续发 `R` 的进程；
     重下位流会复位 FPGA 并让固件重新等待 `R`。
- 成果：512 拍窗口，IPC 0.635 / CPI 1.575（板级整段 1.5388，差 2.3%），
  窗口内 84.3% 提交落在 `__mulsi3` 软件乘法循环。证据与复现见 `release/evidence/ila_coremark/README.md`。

### 2026-09-17 / CPI 专项：取指每两拍一条，把 CPI 钉在 2.34（**Score 最大单项损失**）

- 现象：实体板 50/80 MHz 两点 `CoreMark/MHz x1000` 都是 591，CPI 2.3443 / 2.3445；
  按每 1000 条指令分解 `2344.3 = 理想 1000 + stall 106.4 + flush 103.3 + 剩余 1134.6`，
  这个「剩余 1134.6（48.4%）」既不是 Hazard stall 也不是 flush，长期没有归因。
- 第一错误点：**取指事务的第二个周期**——请求被接收后的那一拍，取指端口没有任何请求在场。
  （不是 EX/MEM 的数据事务，也不是 Hazard 逻辑。）
- 第一错误信号：`i_req_valid` 在窗口 1,788,110 拍中有 **920,207 拍（51.5%）为低**；
  相邻 IF/ID 写入间隔直方图里 **间隔 2 占 664,411 次（86.7%）、间隔 1 只有 1 次**。
- 预期与实际：`docs/interfaces.md` §3 明确要求「流水线 IF 允许在旧取指响应完成握手的同一拍接受下一请求，
  以支持一拍一条的连续取指」；实际每笔取指固定占 2 拍，1,532,008/1,788,110 拍（85.7%）是取指底座，
  其中 **768,832 拍（43.0%）纯属取指串行化损失**。
- 根因（两处，缺一不可）：
  1. Core：`pipeline_cpu.v` 在 `if_request_accept` 当拍 `if_req<=0`，而重新登记 `if_req_addr_reg`
     要等到“响应被接收”那一拍的结尾（`if(!if_req)` 分支），因此下一拍请求不可见，
     “旧响应接收 + 新请求接受”的同拍交接永远无法发生。
  2. SoC：实体板取指存储器 `assign req_ready=!rsp_valid`，在交接当拍（`rsp_valid=1 && rsp_ready=1`）
     恰好为 0，即使 Core 把请求送到也会被拒收。
- 最小修复：Core 新增 `if_arm`（接受请求当拍立即武装下一笔请求，展示地址直接来自已寄存的 `fetch_pc`，
  不新增地址寄存级，`!ready` 时地址仍稳定；Redirect 当拍先冻结成 `if_req` 再改 `fetch_pc`）；
  取指存储器 `req_ready` 改为 `!rsp_valid||rsp_ready`（数据端口不变，`dstate` 已串行化）。
  详见 `docs/rtl_changes.md` 改动 2。
- 归因方法（可复现）：新建只读观测台 `tb/tb_cpi_attribution.v` + `tb/cpi_board_memory_model.v`
  （与 `coremark_imem`/`coremark_dmem` 逐拍一致），口径自证：观测台 CPI **2.342** vs 实体板 **2.3443**。
  单改 SoC 侧 ready 策略收益只有 2.342 → 2.321（−0.9%），证明瓶颈在 Core。
- 验证：-Quick 与全量回归 `ALL AUTOMATED FINAL REGRESSION PASS`；官方 CoreMark RTL 仿真
  cycles 1,852,156 → 1,295,932；实体板 50 MHz Score 29.559 → **45.051**、CPI 2.3443 → **1.5388**、
  22.196 s、四 CRC 全过；80 MHz PLL Score 47.295 → **72.081**、CPI 1.5387；逻辑分析仪 50/80 MHz 各 80/80 PASS。
- 影响：只改 Core 内部取指握手与 Core 外取指 adapter 的 ready 策略。Core 顶层端口、单 outstanding 语义、
  提交级 trace 语义、Reference Model 等价性全部不变；80 MHz WNS 由 +0.145 ns 变为 +0.667 ns（更好）。

### 2026-09-17 / CPI 专项：load-use 停顿计数 3 → 4（测试期望按新时序纠正，非放宽）

- 失败测试：`scripts/run_pipeline_load_use_tb.ps1`（固定延迟编译）报 `LOAD STALL COUNT FAIL got=4 want=3`。
- 第一错误点：`tb/data/load_use.mem` 中 `0x24 lw x7,0(x0)` → `0x28 add x8,x1,x7` 这一对的 ID/EX 周期。
- 第一错误信号：`event_load_stall` 在该对指令上多出一次脉冲（`LOADUSE cyc=27 ex_load_pc=00000024 id_pc=00000028`）。
- 预期与实际：该程序共有 **4 组相邻 load-use**（0x08→0x0c、0x10→0x14、0x18→0x1c、0x24→0x28），
  满速取指下 4 组都必须检出；旧期望值 3 是“取指每两拍一条”时代的历史标定——
  当时取指空洞恰好插在 0x24→0x28 之间，把这对相邻指令在流水线里拉开成两级，
  既不构成 load-use、也不需要停顿。
- 根因：不是 RTL 缺陷，而是旧值把“前端串行化顺带掩盖了一个真实冒险”误当成正确基线。
- 最小修复：`EXPECT_LOAD_STALL` 3 → 4，并在脚本内写明理由；同时用一次性探针
  （`tmp/cpi/probe_loaduse.v`）逐事件打印 4 次 `LOADUSE` 的 PC 对，确认与程序里的 4 组 hazard 一一对应。
- 验证：同测试的**提交级 trace 与最终 architectural state 对比全部 PASS**；
  `scripts/run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`。
- 影响：仅测试期望值；流水线功能、接口与 Reference Model 不受影响。

### 2026-09-17 / 工具：频率扫描汇总把 `Minimum Pulse Width` 当成 setup WNS

- 最小复现：`scripts\run_fmax_sweep_rtl.ps1 -Tag cpi -Periods '11.765,11.111'`，
  再看 `tmp/fmax_sweep/cpi_sweep_summary.csv` 与同目录的 `report_timing/*.rtr`。
- 现象：85 MHz 汇总写 `WNS=4.365`、90 MHz 写 `WNS=4.038`，而 `.rtr` 的
  `Setup Summary(Slow Corner)` 实际是 `+0.393` / `−0.374`；4.365 其实是
  `Minimum Pulse Width Summary(Slow Corner)` 的 slack。
- 第一错误点：汇总脚本的报表解析（不是 PDS、不是 RTL）。
- 根因：原解析用“第一个形如 `名字 名字 数字 数字 整数 整数` 的行”取 WNS/WHS，
  而报告里 `Recovery/Removal/Minimum Pulse Width/Setup(Fast Corner)` 等小节是同一形态。
- 最小修复：改为**按小节定位**——先记录当前小节名（`^名字:`），只在
  `Setup Summary(Slow Corner)` 取 WNS/TNS/失败端点、在 `Hold Summary(Slow Corner)` 取 WHS/THS；
  并从 `Performance Summary` 行额外记录估计 Fmax。同时修正小节名捕获的正则
  （原正则贪婪匹配只捕到 `Setup Summary`，漏掉 `(Slow Corner)` 后缀）。
- 验证：`-Tag cpi3 -Periods '11.765,11.111'` 汇总输出
  `f84998 WNS=0.393 fail=0 WHS=0.231 MET`、`f90001 WNS=-0.374 fail=102 WHS=0.312 VIOLATED`，
  与手工从 `.rtr` 读取的数值逐字段一致。
- 影响：仅扫描汇总脚本；`docs/performance_tuning.md` 中的历史 WNS 数字本来就直接取自 `.rtr`，不受影响。

### 2026-09-17 / 工具：`run_coremark_fpga_tb.ps1` 会静默把板级镜像恢复成“未窗口对齐”版本

- 最小复现：跑一次 `scripts/run_coremark_fpga_tb.ps1`，再检查 `fpga/coremark/rtl/coremark_imem.mem`
  是否还含 `start_time()` 的 `PERF_CONTROL` 写（`... 100027B7 00100713 02E7AC23`）。
- 现象：脚本 `finally` 恢复最终 1000 迭代镜像时漏传 `-PerfWindowAlign 1`，使仓库源码退回未对齐版本，
  与已经实体板实测通过的位流不一致；板级 CPI 归因依赖这个对齐窗口（否则 `COREMARK_READY`
  的 UART 轮询会进入计数窗口，产生 `stall > cycles` 的失真数据）。
- 根因：恢复步骤只对齐了 `-Iterations/-ClockHz/-AutoStart`，漏了观测口径开关。
- 最小修复：`finally` 中补 `-PerfWindowAlign 1`，并加注释说明为什么不能省。
- 验证：修复后重跑 `run_coremark_fpga_tb.ps1`，`coremark_imem.mem` 仍含窗口对齐的写操作。
- 影响：仅镜像生成脚本；不改被测执行路径。

### 2026-09-17 / Task 33：发布证据把综合与布局布线两个阶段的资源数字混排

- 最小复现：运行 `scripts/run_release_evidence.ps1`，比较 `release/evidence/automated_metrics.json` 的 `ff` 与 `docs/progress.md`、`release/HANDOFF.md`、技术报告中引用的 `3129 FF`。
- 第一错误点：`python/release_evidence.py` 的 `utilization()` 解析逻辑；不是 PDS 综合、时序或实体板问题。
- 预期与实际：`fpga/logic_analyzer/flow.log` 综合段为 LUT 3459 / 寄存器 3129 / DRM18K 5.5，device map 段为实现 FF 3120；旧实现从综合段取 LUT 与 DRM，却从 device map 段取 FF，生成 `3459 LUT + 3120 FF + 5.5 DRM` 的混合行，与全部已发布材料不一致。
- 根因：`utilization()` 在 `Device Utilization Summary` 块内匹配 `| FF |`，而 `Total LUTs`/`Total DRM18Ks` 来自综合统计，两者属于不同阶段。
- 最小修复：FF 改取综合统计 `Total Registers`（3129），并新增 `ff_implemented`（3120）单独保留布局布线后实现值；`automated_metrics.md` 增加一行阶段说明。不修改任何综合或时序结论。
- 回归：`run_release_evidence.ps1` 输出 `ALL RELEASE EVIDENCE TEST PASS`；JSON 为 `lut=3459, ff=3129, ff_implemented=3120, drm=5.5, setup=2.661, hold=0.312, fmax=57.6735`，与 `fpga/logic_analyzer/synthesize/mes50hp_logic_analyzer_top.snr` 的综合行一致；`create_release_manifest.ps1` 与 `audit_release_package.ps1` 仍 PASS。
- 影响：仅发布证据提取脚本与证据文件；不影响 RTL、Core/SoC 接口、时序或实体板结论。

### 2026-09-17 / Task 33：交付包早于最终位流，审计哈希与实体证据不一致

- 最小复现：运行 `audit_release_package.ps1` 检查最终包哈希，或比较 `release/final_submission/bitstream/mes50hp_riscv_logic_analyzer.sbit` 与 `fpga/logic_analyzer/generate_bitstream/mes50hp_logic_analyzer_top.sbit`。
- 第一错误点：交付导出时间戳（09-17 08:37）早于 J8 约束校正、Capture Engine 分频边沿修复与最终 PDS 重建（13:45～13:47）；不是 RTL、时序或综合问题。
- 预期与实际：审计期望位流 SHA-256 `2C09E690…`（实体板 80/80 回环所用），实际包内为 `01C394618BB473E6…`；同时 `evidence/logic_analyzer_board_final` 缺失，`.fdc` 仍写连续脚对 `3..18`，`capture_engine.v`、`logic_analyzer_pattern_gen.v` 与三份上位机工具均为修复前版本。
- 根因：实体回环修复与最终位流重建之后没有重新执行导出与发布清单。
- 最小修复：重新运行 `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1`；不修改任何源文件。
- 回归：三条命令分别输出 `FINAL SUBMISSION EXPORT PASS files=215`、`RELEASE MANIFEST PASS files=1221`、`RELEASE PACKAGE AUDIT PASS final_files=132 artifacts=3`；位流三处副本 SHA-256 一致；`run_final_regression.ps1 -Quick` 输出 `ALL AUTOMATED FINAL REGRESSION PASS`。
- 影响：不影响 Reference Model、Core/SoC 接口或架构文档；仅交付产物一致性。

### 2026-09-17 / 发布脚本：PowerShell 5.1 解码与 .NET Core API 依赖

- 最小复现：本机仅 Windows PowerShell 5.1（ACP=936）时运行 `powershell -File scripts/audit_release_package.ps1` 报 `missing release/final_submission/鍚姩…cmd`；`export_final_submission.ps1` 在写清单时报 `[System.IO.Path]` 不包含 `GetRelativePath`。
- 第一错误点：解释器与脚本编码/API 契约，不是发布内容本身；导出已在复制阶段完成后失败，包内没有 `SHA256SUMS.txt` 且 zip 仍是旧文件。
- 根因：无 BOM 的 UTF-8 脚本被 PS 5.1 按 GBK 解码，中文字符串与文件名损坏；`Path.GetRelativePath` 属 .NET Core/.NET Standard 2.1，.NET Framework 4.x 不提供。
- 最小修复：为 `audit_release_package.ps1`、`export_final_submission.ps1`、`create_release_manifest.ps1`、`generate_coremark_fpga_memory.ps1` 补 UTF-8 BOM，并统一用 PowerShell 7 执行发布脚本（本机为 Codex 运行时 `C:\Users\xwc\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`，7.6.5）。
- 回归：用 pwsh 7 重跑导出、清单与审计全部 PASS；其余 91 个纯 ASCII 脚本在 PS 5.1 下不受影响。
- 影响：仅发布工具链可移植性；不改变 RTL、Testbench 接口或验证结论。

### 2026-09-17 / Task 30：分频采样丢失 UART 边沿触发

- 最小复现：MES50HP J8 物理回环运行 UART `0xA5`，旧实现返回 `UART decode mismatch`；静态和计数器模式正常。
- 第一错误点：`capture_engine.previous_sample` 在非 `sample_tick` 周期被更新，导致发生在两个有效采样点之间的下降沿只保持一个系统时钟并在采样前消失。
- 根因：边沿检测把“上一系统时钟值”误当成“上一有效采样值”，分频采样时触发点可能落入 UART 数据位内部。
- 最小修复：Arm 时锁存当前输入，之后仅在 `armed && sample_tick` 时更新 `previous_sample`；同时让 UART pattern restart 先输出完整 idle-high 位，并由 Python 在位中心解码。
- 回归：新增 `divided edge retained` 定向测试；Capture Engine、MMIO、SoC、board-top 和 Python 全部 PASS。PDS 50 MHz All Constraints Met，JTAG 下载 DONE=1；static/counter/UART/SPI 各 20 次，共 80/80 实体回环 PASS。
- 影响：不改变 CPU Core 或 Core/SoC 接口；修复范围仅为 Core 外采集外设、发生器和上位机解码。

## 当前记录

### 2026-09-17 / 性能调优轮：冻结范围审计脚本依赖外部 rg，长期处于静默失效状态

- 最小复现：运行 `scripts/run_scope_audit.ps1`，当前环境报 `The term 'rg' is not recognized`。
- 第一个错误点：脚本第 6 行对 `rg` 的调用，不是 RTL、时序或综合问题。
- 预期与实际：审计应当扫描 `rtl`、`fpga/logic_analyzer`、`software/logic_analyzer`、`python`
  并拒绝已冻结功能（RLE/Cache/异常中断/AI/DDR/HDMI/PCIe/千兆网/I2C/16 通道）的实现；
  实际上 `rg` 不在 PATH 上，`2>$null` 又把"命令未找到"吞掉，
  于是 `$violations` 恒为空、脚本无条件走到 `SCOPE AUDIT PASS`。
- 根因：审计实现依赖外部可执行文件且隐藏了失败；`ErrorActionPreference=Stop` 无法捕获非终止的错误流重定向。
- 最小修复：`run_scope_audit.ps1` 改为纯 PowerShell 实现（`Get-ChildItem` + `Select-String`），
  显式排除 PDS 构建产物（`generate_bitstream`/`synthesize`/`place_route` 等）与 `__pycache__`，
  并新增正向断言（BTB 必须是 `valid[0:15]` 16 项 + `counter[0:15]` 2-bit）。
- 验证：注入一个含 `cache` 字样的临时文件后审计报 `FROZEN FEATURE SCOPE AUDIT FAIL` 并以非零码退出；
  删除后输出 `SCOPE AUDIT SCANNED files=47` 与 `SCOPE AUDIT PASS`。
  **注意**：该修复意味着此前若干轮记录的"Task 33 冻结范围审计 PASS"不具备证据效力，本文件在此更正。
- 影响：不改变 RTL、Core/SoC 接口或时序结论；仅让审计恢复真实检测能力。

### 2026-09-17 / 性能调优轮：板级性能计数器窗口未对齐，导致 CPI 归因完全失真

- 最小复现：下载 50 MHz CoreMark 位流（`PERF_WINDOW_ALIGN=0`），
  运行 `python/coremark_serial.py COM11 --clock-hz 50000000`，读 `PERF` 行。
- 第一个错误点：`perf_monitor` 的 `cycle_count` / `stall_count` 等计数器是**自由运行**的，
  从复位释放一直累加到 `portable_fini()` 回读时刻，**不**只在 CoreMark 计时窗口内计数。
- 预期与实际：预期 `stall/cycles` 在 5%~15% 量级；
  实际出现 `stall` **超过** `cycles`（1.70e9 vs 2.84e9 的旧数据里），
  修正前一次读数甚至出现 `branch` 超过 `instret`——物理上不可能，说明窗口口径错误。
- 根因：`COREMARK_READY` 会先等上位机发 `R` 才开跑，那段轮询是紧凑的 load+branch 循环，
  每次都要走统一事务（含固定 2 拍握手），因此产生上亿次 stall 与 branch，
  把 CoreMark 内核的真实 CPI 完全淹没。
- 最小修复：在 `software/coremark/core_portme.c` 的 `start_time()` 中加入
  `PERF_CONTROL = 1u`（写 perf_mmio CONTROL，字节偏移 0x38）清零计数器，
  由 Makefile 开关 `PERF_WINDOW_ALIGN` 控制（默认 0，保持历史镜像逐字节可比；
  正式板级归因镜像用 1）。该语句只改观测口径，不改被测量的执行路径。
- 验证：对齐后 50 MHz 实测 `cycles=1,693,816,436`、`ticks=1,691,496,677`，
  窗口差仅 0.14%（对齐前为数亿周期）；CPI 2.3443，与 RTL 仿真的 2.3747 相差 1.3%。
  80 MHz PLL 镜像独立复现：CPI 2.3445、`stall/cycles` 4.53%，与 50 MHz 逐项吻合到 0.02% 以内。
- 影响：**历史 `release/evidence/coremark_board.json` 的七项计数器不可用于 CPI 归因**
  （`ticks`/`score` 字段仍有效）；`docs/coremark_cpi_analysis.md` 已改为以
  `coremark_board_opt50m_aligned.json` 为准。不改变任何 RTL 或架构结论。


### 2026-09-15 / Task 30：Task 30 栈顶与互连 RAM 上界不一致

- 最小复现：将裸机栈顶扩大到 `0x1000` 后运行 `run_logic_analyzer_soc_tb.ps1`，软件读取的 `post_count` 变为 8192。
- 第一错误点：函数栈访问地址超过互连原 `0x3FF` RAM 窗口，返回 error/zero，随后局部变量被破坏。
- 根因：DMEM adapter 已扩大到 1024 words，但 SoC 互连仍用 1 KiB byte 地址上界。
- 修复：Task 30 board wrapper 与 SoC TB 同步使用 `RAM_LAST_ADDR=0x0FFF`，启动代码用 `lui sp,1` 设置栈顶；Core 与统一事务接口不变。
- 验证：AUTOSTART SoC 报告 `count=10 trigger_index=4 post_cfg=4`，交互式 board-top 亦 PASS。

### 2026-09-15 / Task 23：数据事务等待跨越 WB 周期时丢失转发值

- 最小复现：较老指令在 WB 写 `rd` 的同周期，较新 ID/EX 指令因 EX/MEM 数据事务等待而保持；等待结束时寄存器文件读快照仍为写回前值。
- 第一错误点：解除 `mem_hold` 后的 EX operand，原 forward unit 此时已看不到前一周期 WB producer。
- 根因：ID/EX 被整体保持时，源操作数快照没有吸收同周期提交的 WB 数据。
- 修复：保持 ID/EX 时若 WB 命中源寄存器，更新相应 operand snapshot；新增 `wb_hold` fixed/random 定向 trace 比较。
- 验证：`run_pipeline_wb_hold_tb.ps1` 两种时序 8/8 trace PASS，Task 23 十入口回归与 Task 24 GCC fixed/random 全部 PASS。

### 2026-09-15 / Task 26～30：PDS recipe 被生成脚本覆盖及大 case ROM 不可实现

- 现象：PDS 会生成或修改 `impl.tcl`，原构建脚本把生成文件误当稳定 recipe；CoreMark 的逐字 case ROM也导致综合规模和时间不可接受。
- 根因：源配方与工具输出未隔离；程序镜像没有利用 PDS 可初始化同步 DRM。
- 修复：每次构建复制只读 `pds_recipe.tcl` 到临时 recipe，并校验源 hash；CoreMark/Task 30 改为固定深度同步数组与 `.mem` 初始化，PDS 日志确认 DRM 映射。
- 验证：Task 26、Task 28、Task 30 均完成 Compile 到 bitstream，50 MHz setup/hold 全部满足；CoreMark 同步 memory board-top 仿真输出官方 CRC。

### 2026-09-14 / Task 33：最终 Regression 聚合器被历史 `exit 0` 提前终止

- 最小复现：`run_final_regression.ps1 -SkipExternal` 直接调用 `run_rv32i_regression.ps1`；Task 12 的第一个独立 Testbench 脚本正常结束时会执行 `exit 0`，父聚合器随后不再继续。
- 第一错误点：回归调度器进程边界，不是 RTL 或 Testbench 结果；日志会停在 Task 12 中段而汇总文件可能保留旧结果。
- 根因：PowerShell 脚本内的 `exit` 终止当前解释器，聚合器用 `& script` 调用时没有隔离子进程；Task 23 也存在相同风险。
- 最小修复：Task 12、Task 23 和最终聚合器统一通过当前可用的 PowerShell 解释器以 `-File` 子进程调用每个入口；保留原有退出码并在失败时停止。
- 验证：Task 12 日志完整包含 22 个入口并输出 `ALL TASK12 REGRESSION PASS`；Task 23 输出 9 个入口；修正后的 `run_final_regression.ps1 -SkipExternal` 输出 `ALL FINAL REGRESSION PASS`，外部模式输出本地 PASS 加 3 项明确 BLOCKED。
- 影响：仅修复回归调度和证据完整性，不改变 Core、SoC、接口或既有 Testbench。

### 2026-09-14 / Task 26/30：PDS 许可证自动发现路径

- 现象：当前 Codex 进程的 `PANGO_LICENSE_FILE`、用户/系统环境变量均为空；PDS 命令行因此报 `Flow-0183`。已检查 PDS 安装目录、`D:\Pango`、`C:\Users\xwc\AppData\Roaming\pango`、`C:\Users\xwc\AppData\Local\pango` 和 `D:\ToolsSoftware\pango`，当前沙箱可见范围未发现 `PDS-*.lic`/`pango*.lic`。
- 处理：Pipeline 与 Task 30 PDS 脚本增加 `-LicenseFile` 参数、标准目录自动发现和未发现时的明确警告；发现合法文件后会自动设置 `PANGO_LICENSE_FILE`，并同时检查 PDS 返回码与 `Flow-0183` 文本。
- 验证：无许可证参数时仍按预期明确失败；使用候选 ModelSim/Intel/Robei 文件会被 PDS 判为格式不兼容，未被误当作 Pango License。
- 影响：不改变 RTL；只要合法 Pango `.lic` 位于自动发现目录或由环境/参数提供，脚本即可直接执行综合，不需要修改工程文件。

### 2026-09-14 / Task 30：逻辑分析仪响应地址未锁存与测试写事务悬挂

- 最小复现：在 Application MMIO 请求接受后立即改变 `req_addr`，或在独立 TB 写请求后不消费写响应。
- 第一错误点：响应等待周期的 `rsp_rdata`/`rsp_valid`；原 wrapper 组合使用当前地址，测试写响应则使 `rsp_valid` 永久保持。
- 根因：设备未在请求握手时锁存读数据/错误位；TB 写任务没有遵守统一 response handshake。
- 最小修复：`perf_mmio` 与 `logic_analyzer_mmio` 在 `req_valid && req_ready` 时锁存响应数据和错误，`capture_engine` 仍只接受一次 arm/stop/clear 脉冲；TB 写任务等待并消费响应。
- 验证：`run_perf_mmio_tb.ps1`、`run_logic_analyzer_tb.ps1`、`run_application_mmio_mux_tb.ps1`、`run_logic_analyzer_soc_tb.ps1` 全部 PASS，并覆盖错误地址、随机背压和软件配置路径。
- 影响：仅修改 Core 外部 MMIO/测试；不改变 `pipeline_cpu` 端口或事务契约。

### 2026-09-14 / Task 30：PDS/实体板/CoreMark 外部证据阻塞

- 现象：本地 RTL、软件和 Python 回归全部通过，但 Task 30 PDS 批处理输出 `Flow-0183`，仓库没有官方 CoreMark 源码，J8 相邻脚对物理回环尚未在当前会话连接。
- 根因范围：许可证、第三方源码授权/下载和真实 MES50HP 设备属于工作区外部状态，不是仿真失败。
- 处理：`run_logic_analyzer_pds.ps1` 与 `run_final_regression.ps1` 明确检测并报告 BLOCKED；不使用其它 benchmark 冒充 CoreMark，不用内部 pattern loopback 冒充物理闭环。
- 影响：不得标记 G9/G10/G11 或 `competition_final`；本地 PASS 证据仍可复现，待具备许可证、源码和实体板后按 `docs/reproduction.md` 重跑。

### 2026-09-14 / Task 23：Redirect 撤回被背压的取指 valid

- 最小复现：`hazard_stress` 使用随机取指背压，并在 taken Branch/JAL 附近令 `i_req_valid=1, i_req_ready=0`。
- 第一错误点：Redirect 周期的取指请求接口；地址仍保持相同，但 `i_req_valid` 在握手前被撤回。
- 预期与实际：契约要求 `valid && !ready` 时 valid 与地址持续稳定；候选流水线把 `i_req_valid` 组合依赖于 `ex_redirect/front_hold`，因此错误变为 0。
- 根因：为提升 IF 吞吐而加入的响应/请求同拍交接没有保留独立的已登记请求槽，Redirect 直接抑制了尚未接受的请求。
- 最小修复：恢复 `if_req` 与稳定的 `if_req_addr_reg`；Redirect 只将等待请求和未来响应标为 discard，请求仍正常握手，返回后丢弃，再从目标 PC 发起新事务。
- 验证：`run_pipeline_hazard_stress_tb.ps1` 固定及随机背压各 20/20 条提交 trace PASS，请求稳定性监视器无错误，两个合法 Store 的请求副作用数与 Store trace 数均为 2；`run_pipeline_reset_abort_tb.ps1` 证明 Reset 可中止未接受 Store 且重启后只写一次。
- 影响：修改流水线 IF 控制，不改变 Core/SoC 端口或单 outstanding 契约；需纳入 Task 23 及后续完整 Regression。

### 2026-09-13 / Task 16：PDS 综合忽略 `$readmemh` 导致板级固件未初始化

- 最小复现：Task 16 SoC 顶层使用 `$readmemh("mmio_demo.mem", ...)` 初始化 IMEM/DMEM 后执行 PDS 综合。
- 现象：PDS 报告 initial block / `$readmemh` 不参与综合；仿真中的 Hello/GPIO 行为不能直接作为下载 bitstream 的固件证据。
- 第一错误点：综合初始化阶段；不是 CPU 指令周期或 MMIO 互连信号错误。
- 根因：该 PDS 流程不会把 Verilog 仿真时存储器初始化自动映射为综合后的 BRAM/逻辑内容。
- 最小修复：将 Task 16 demo 的 24 个镜像字改为综合可见的 Verilog 常量函数；保留 `mem/mmio_demo.mem` 作为仿真/追踪参考文件，并保持单周期 CPU 与 SoC 接口不变。
- 验证：`run_soc_harness_tb.ps1` 19/19 PASS，`run_mes50hp_soc_demo_tb.ps1` 的双行/30 字节连续 UART 检查 PASS；PDS Compile→Synthesize→Map→Place→Route→Timing→Bitstream 完成，50 MHz 下预计 59.0179 MHz、WNS 3.056 ns、TNS 0，综合日志不再出现 `$readmemh` 警告。
- 影响：当前 bitstream 固化为持续输出版 Task 16 demo；更换固件需重新生成常量并重新实现。尚未进行实体板下载与串口验收。

### 2026-09-13 / Task 16：UART 无输出的根因是缺少独立 USB-UART 数据线

- 最小复现：仅连接供电线与 JTAG 下载线，Windows 只枚举 FTDI 下载器的 COM9/COM10，未枚举底板 CP2102。
- 第一错误点：FPGA 外部的 USB-UART 物理连接；不是 `uart_mmio`、CPU、UART 波特率状态机或 FPGA 管脚约束。
- 根因：MES50HP 的 JTAG 与底板 CP2102 USB-UART 是独立链路；未插 USB-UART Type-C 数据线时，串口工具打开的是下载器通道。
- 修复：保留电源/JTAG，同时连接底板 USB-UART Type-C 数据线，使用 CP2102 的 COM 口，以 115200、8N1、无流控接收。
- 验证：当前 PDS map 为 `uart0_tx LOC=R9`、`uart0_rx LOC=R8`；实体板串口持续、无乱码地显示 `Hello RISC-V!`。
- 影响：UART TX 的实体板链路已通过；GPIO 的 `0xAA` LED 实物图仍需补充后才能宣布 Task 16 / G5 完成。

### 2026-09-12 / Task 12：未对齐 Load 会错误写回零值

- 最小复现：DMEM word 0 为 `32'h80FF_7F01`，先执行 `addi x2, x0, 0x55`，再执行未对齐的 `lh x2, 1(x1)`，其中 `x1=0`。
- 现象：`load_store_unit` 已将 `misaligned` 置 `1` 且 `load_data` 保持默认 `0`，但 CPU 仅以该信号抑制 `dmem_we`；RegFile 仍接收原始 `reg_write`，使 `x2` 被错误写成零值。
- 第一错误点：RegFile 写使能连接 `rd_we=reg_write`；第一个错误状态更新是未对齐 Load 周期的寄存器写回。
- 根因：未对齐策略只覆盖 Store，没有将 Load 的 `misaligned` 检测接入 RegFile 写使能。
- 最小修复：增加 `reg_write_effective = reg_write && !(mem_read && misaligned)`，并将 RegFile 的 `rd_we` 改接该信号；保留已有 `dmem_we = mem_write && !misaligned` 与顺序 `PC+4` 行为。
- 验证：运行 `./scripts/run_single_cycle_load_align_tb.ps1`，6/6 PASS：未对齐 `LH` 不改变哨兵 `x2=0x55`；对齐 `LHU/LB/LBU/LW` 写回分别为 `0x000080FF`、`0xFFFFFF80`、`0x00000080`、`0x80FF7F01`。运行 `./scripts/run_single_cycle_store_align_tb.ps1`，6/6 PASS：`SB`、两个对齐 `SH` 与 `SW` 按 byte strobe 更新，未对齐 `SH` 不改变 DMEM。现有单周期、JALR、U-Type、SLTI、Shift-Immediate、Logic-Immediate 回归亦全部 PASS。
- 影响：当前无异常单周期模型仅保证自然对齐 Load/Store；未对齐访问检测后不产生 RegFile 或 DMEM 写副作用，但不实现 trap。该限制须在 Task 12 覆盖表和后续 Core/SoC 文档中保持一致。

### 2026-09-10 / Task 10：MES50HP JTAG/LED 冒烟通过

- 最小复现：下载 `fpga/mes50hp_bram_smoke` 的 bitstream，使用 `P20` 作为 50 MHz 时钟，观察 `LED1=B2`。
- 现象：PDS 首次扫描板载 SPI Flash 报 `JtagServer-0335` / `Configuration-0008`；改为确认 JTAG FPGA 链并下载临时 bitstream 后成功，`LED1` 常亮。
- 第一错误点：Flash 扫描路径；不是 RTL、PDS 综合或 BRAM 逻辑错误。
- 根因范围：Flash 扫描与 FPGA 临时配置是不同下载路径；当前已验证 JTAG FPGA 配置路径正常，Flash 固化路径暂不作为本次 BRAM 冒烟前置条件。
- 验证：PDS Compile/Synthesize/Device Map/Place & Route/Timing/Generate Bitstream 已完成；实体板首次下载后 LED1 PASS，随后再次下载同一 bitstream 后 LED1 仍 PASS。当前不要求断电，因为 bitstream 尚未固化到 SPI Flash。
- 影响：Task 10 / G2 正式 PASS。SPI Flash 固化路径仍需单独排查，但不影响本次临时 JTAG FPGA 冒烟证据。

### 2026-09-08 / Task 10：PDS 批处理缺少许可证环境变量

- 最小复现：执行 `D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe -project D:\RISC_V_CPU_2026\fpga\bram_smoke\bram_smoke.pds -run cmd_synthesize`。
- 现象：PDS 在读取工程之前退出，输出 `Flow-0183: Environment variable PANGO_LICENSE_FILE is not set. Check license failed.`。
- 第一错误点：PDS 许可证检查；尚未进入 Verilog 编译、器件核对或 `.fdc` 解析，因此没有 RTL 周期/信号错误。
- 根因范围：当前 Windows 会话未配置本机 Pango PDS 的合法许可证路径或许可证服务器。
- 最小修复：通过 PDS 的许可证配置或用户已有许可证设置 `PANGO_LICENSE_FILE`，重启 PDS / PowerShell 后重跑同一命令；不得跳过许可证检查或改用其他器件。
- 验证现状：PDS 图形界面已使用其现有许可证完成首轮 Compile、Synthesize、Device Map、Place & Route、Timing 和 bitstream 生成；命令行仍不可直接复现该流程。
- 影响：阻塞可复现的 PDS 批处理，但不阻塞用户已授权的 GUI 流程；不影响 IMEM/DMEM 行为级模型的已通过回归。

### 2026-09-08 / Task 10：首轮“BRAM 冒烟”被综合器裁剪为分布式 RAM

- 最小复现：检查首轮 PDS 综合输出 `fpga/bram_smoke/synthesize/apm_drm_lutram_utilization.log`。
- 现象：原 RTL 声明为 256×32 RAM，但报告实际为 `2 x 3 bit`、`GTP_RAM32X1SP/GTP_RAM32X2SP`；没有块 RAM/DRM 资源。
- 第一错误点：综合优化阶段；固定写入两个地址和固定数据使未观测的数组空间可被裁剪，PDS 行为符合逻辑优化规则。
- 根因：自检覆盖不足，不能以 RTL 中的数组声明替代综合后的真实资源证据。
- 最小修复：测试改为 1024 个动态地址和 LFSR 数据的全覆盖写入、同步读和逐字比较，重新综合后必须以资源报告确认真实块 RAM/DRM 映射。
- 验证现状：修改后的独立 Icarus 测试已输出 `ALL BRAM SMOKE TEST PASS`；修改后的 PDS 资源报告尚未生成。
- 影响：先前生成的 `.sbit` 不得下载作为 BRAM 验收证据；Task 10 Gate 仍未通过。

### 2026-09-07 / Task 10：OSS CAD Suite 的 VVP 运行时启动崩溃

- 最小复现：执行 `D:\oss-cad-suite\bin\vvp.exe -V`，以及运行只包含 `$display` / `$finish` 的空 Testbench。
- 现象：Windows 弹出 `vvp.exe - 应用程序错误`，报告指令引用不可读内存；仿真终端无 PASS/FAIL 输出。
- 第一错误点：`vvp.exe` 进程启动阶段；尚未进入 RTL 的时间 0 仿真事件，因此不存在错误 RTL 信号或周期。
- 根因范围：OSS CAD Suite 内置的 Icarus 14.0 development (`s20260301-363-g1d2aa1b6f-dirty`) VVP 运行环境故障；与 DMEM、动态数组索引和 Testbench 时钟驱动无关。
- 最小修复：保留原工具目录但停止使用其 VVP；将 Icarus Verilog 12 Windows 稳定包独立安装到 `D:\Tools\iverilog-v12`，仿真脚本默认选择该目录，并允许用 `-IcarusRoot` / `IVERILOG_ROOT` 覆盖。
- 验证：稳定版 `vvp -V` 正常；Task 4～10 当前基础模块回归全部 PASS：RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store Unit 35/35、DMEM 14/14。
- 影响：仅本地仿真工具链；不影响 RTL 架构、Core/SoC 接口或 Reference Model 行为。Task 10 仍需 IMEM 与 PDS/BRAM 冒烟后才能通过。

### 2026-09-03 / Task 3：Windows ISA 检查命令不兼容

- 最小复现：在 Windows PowerShell 的 `software/hello_uart` 目录执行 `make all`。
- 现象：ELF、反汇编和镜像均已生成，但 `check-isa` 调用 Linux `grep` 失败，`make` 返回 Error 2。
- 根因：Makefile 使用了 Windows 环境中未提供的 Linux `grep` 命令。
- 最小修复：将该检查替换为 Windows `cmd /c findstr`；不改动 C 源码、链接脚本、生成物格式或 ISA 约束。
- 验证：执行 `make clean; make all`，输出 `TASK3 ISA CHECK PASS: RV32I-only disassembly`。
- 影响：仅构建脚本兼容性；不影响 CPU 架构、Reference Model、Core/SoC 接口或 RTL。
