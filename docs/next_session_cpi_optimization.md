# 新会话指令（把本文件全文粘贴给新会话即可）——CPI 优化专项

> 项目规则 `AGENTS.md` / `AGENTS.local.md` 会自动加载，无需重复。以下是增量信息与本次任务的明确授权。

---

## 0. 授权声明（覆盖 AGENTS.md 2.1 默认限制）

**用户已明确授权直接修改 RTL。** 本任务中你可以编辑、新增、替换 `rtl/` 下的 Verilog 源文件
（重点是 `pipeline_cpu.v`），不必只提供模板让用户手写。但仍必须遵守：

- 修改前说明依据与预期影响，修改后报告验证结果。
- **一次只动一块，不顺手大重构。** 每轮改动单独给 Before/After。
- 不改模块名与已确定端口，除非有明确理由并写入文档。
- 不把外设专用逻辑塞进 CPU Core（边界见 `docs/interfaces.md`）。
- **每次 RTL 改动后必须重跑** `scripts\run_final_regression.ps1 -Quick`，必须 PASS。
- **每次 RTL 改动后必须重新下载位流并在实体板上实测 CoreMark**（JTAG 线现在已接好、可用）。

---

## 1. 本次唯一的战略目标

**把 CoreMark/MHz 从 0.591 提上去。** 这是当前评分里唯一的短板，也是唯一还没认真打过的一场仗。

赛道评分（赛题一）三项性能指标：`Score = Iterations / (Total_Time × Frequency)`
= **CoreMark/MHz，频率归一化**。

- 提频率**不提高** Score（已用实体板证明：50 MHz Score 29.559、80 MHz Score 47.295，
  比值 1.600 = 80/50，两者 `CoreMark/MHz x1000` 都是 **591**）。
- 提频率只服务独立的第 (2) 项「时钟频率」，**该项已完成，不要再碰**（80 MHz PLL 实跑通过，
  85 MHz 时序 All Met，天花板 89–90 MHz）。
- **要提 Score 必须降 CPI。** 这就是本次任务的全部内容。

### 当前 Score 的量化定位

| 项 | 当前值 | 同类五级流水线+BTB 常见区间 | 差距 |
|---|---|---|---|
| CoreMark/MHz | **0.591** | 1.0 ～ 1.5 | **差 1.7～2.5 倍** |
| CPI | **2.3443** | 1.2 ～ 1.6 | 有 0.7～1.1 的可压缩空间 |

**把 CPI 压到 1.6 就等于 Score 提升约 46%**（0.591 → 约 0.86）。这是本次任务的价值所在。

---

## 2. 当前精确状态（全部实体板实测，直接引用，不要重测）

### 2.1 实测性能（`PERF_WINDOW_ALIGN=1` 镜像，计数器与 ticks 同口径）

| 指标 | 50 MHz 实体 | 80 MHz PLL 实体 | RTL 仿真（Predictor On，ITERATIONS=1） |
|---|---:|---:|---:|
| Score | 29.559 | 47.295 | — |
| CoreMark/MHz x1000 | 591 | 591 | — |
| ticks | 1,691,496,677 | 4,228,738,028 | — |
| 运行秒数 | 33.829 | 52.859 | — |
| cycles | 1,693,816,436 | 4,232,437,933 | 1,852,156 |
| instret | 722,513,265 | 1,805,240,083 | 779,952 |
| **CPI** | **2.3443** | **2.3445** | 2.3747 |
| cycles / iteration | 1,693,816 | 1,692,975 | 1,852,156 |
| stall / cycles | 4.54% | 4.53% | 9.51% |
| load-use / stall | 9.30% | 9.32% | 11.23% |
| flush / cycles | 4.41% | 4.41% | 8.80% |
| branch / instret | 0.275 | 0.275 | 0.274 |

官方 CRC 全过（crcfinal 50 MHz = `0xd340`，80 MHz = `0x5275`），
`Correct operation validated.`，运行 ≥10 s。两个频率点归一化后逐项吻合到 0.02% 以内。

证据：`release/evidence/coremark_board_opt50m_aligned.json`、`coremark_board_80m_aligned.json`、
`coremark_uart_opt50m_aligned.log`、`coremark_uart_80m_aligned.log`。

### 2.2 CPI 分解（每 1000 条指令）

```
cycles 2344.3  =  理想 1000（42.7%） + stall 106.4（4.5%） + flush 103.3（4.4%） + 剩余 1134.6（48.4%）
```

**「剩余 1134.6 拍 = 48.4% 的周期」就是本次任务的靶心。** 它既不是 Hazard stall 也不是 flush。

### 2.3 已知的强相关线索

- **CoreMark 静态指令里 load/store 占 23.6%**（`software/coremark/build/coremark.dis` 统计：
  lw 10.6% + sw 8.9% + 其它访存 4.1%）。动态占比估计 15%～20%。
- 按 17% 动态占比摊销，那 1134 拍相当于 **每次访存额外付出约 6 拍**。
- 机制假设（**待第 3 节实验证实，不许直接当结论**）：`rtl/pipeline_cpu.v` 的数据事务会让
  `dstate` 走 `D_REQ → D_RSP` 两拍，期间 `mem_block` 拉高，EX/MEM 持有、ID/EX 保持、
  IF 也停——**一次访存不是让这一条等，而是把它后面整条流水线一起冻住**。
- 在**零等待**的 RTL 仿真 memory model 下（`tb/ram_adapter.v`）这条路几乎不花钱，
  所以仿真 CPI 2.37 看起来正常，**实体板却只能到 0.591 CoreMark/MHz**。
  这解释了"仿真好看、板上难看"的现象。

### 2.4 已经确定不用再做的事

- **不要再提频率。** 80 MHz PLL 已实跑通过，85 MHz 时序 All Met，天花板 89–90 MHz
  （限制路径是 `core/rf/regs/iGopDrm` → ALU → 预测校验 → `core/*_pc`，属流水线本体）。
- **不要再优化 perf 计数器。** 上一轮已把事件打一拍，`perf/flush_count` 已从最差 10 条路径中消失。
- **不要动面积。** 3458 LUT（含应用）已经是优势项，CoreMark/LUT 8.55/1000 LUT 不错。

---

## 3. 任务清单

### T1（**第一步，必做，不许跳过**）：把「那 1134 拍」精确定位到指令与状态

**目的**：把"剩余 48.4% cycles"归因到具体的 PC / 指令类型 / `dstate` / 阻塞来源，
而不是继续用"访存大概很贵"这种猜测。遵守项目规矩：先定位第一个错误周期和第一个错误信号。

**做法**（建议，可自行改进但要能复现）：在 `tb/` 下新建一个**只读观测**的 Testbench
（不改 RTL、不动被测接口），用 `tb/ram_adapter.v` 但把**数据侧延迟设成与实体板一致的 2 拍**
（关键！仿真默认零等待是失真的根源），并在每个周期采样：

- `core.dstate`、`core.mem_block`、`core.mem_done`、`d_req_valid`/`d_req_ready`/`d_rsp_valid`/`d_rsp_ready`
- `core.exmem_valid`、`core.exmem_memread`、`core.exmem_memwrite`、`core.exmem_pc`
- `trace_pc` / `trace_instruction`（提交级）

输出统计表，至少回答：

1. `mem_block` 一共占了多少周期？占总 cycles 的百分比？（**先验证它是不是那 1134 拍的主体**）
2. 每次**数据访存**平均阻塞多少拍？load 与 store 分别是多少拍？（store 不需要数据返回，理论上不该等响应）
3. 每次**取指**平均阻塞多少拍？
4. 是否存在"访存阻塞期间 IF/ID 也一起停"的放大效应？量化放大倍数。
5. 阻塞最多的前 10 个 PC / 指令。

**验收**：给出可复现的统计数字，且各项之和与总 cycles 对得上（误差 <2%）。
**这一步不做完，不许改 RTL。**

### T2：按 T1 的数据，选一个候选实施（一轮一块）

按预期收益排序的候选（**必须由 T1 数据证实后再动手，不许凭感觉**）：

1. **store 提前退休**：`d_req_ready` 恒为可接收，store 在请求被接收当拍即可退休，
   不必等 `D_RSP`。预期省 1 拍/次 store（静态占 8.9%）。
2. **数据事务与流水线重叠**：让 `dstate` 的等待不要把 ID/EX 与 IF 一起冻住——
   只要 EX/MEM 持有、后续级用 bubble 顶住即可（类似 IF 侧已有的"请求保持 + 响应交接"做法）。
   这是预期收益最大的一项。
3. **缩短数据事务拍数**：把 REQ→RSP 两拍压成一拍。
4. **访存地址提前产生**：若 T1 显示地址在 EX 才算出导致额外等待，可考虑提前。

**每轮必须严格执行这个顺序**：

```
记录 Before（实体板：Score / CPI / ticks / stall / flush；时序：WNS / LUT / FF）
→ 单点最小改动
→ run_final_regression.ps1 -Quick（必须 PASS）
→ 重新综合出时序（必须 All Constraints Met）
→ 重新下载位流 + 实体板实测 CoreMark（必须 CRC 全过 + ≥10 s）
→ 记录 After
```

**一轮只动一块，单独给 Before/After。不允许"改了好几处然后宣称整体提升"。**

### T3：结论与文档

- 更新 `docs/coremark_cpi_analysis.md`（归因数据）与 `docs/rtl_changes.md`（逐改动 Before/After）。
- 更新 `docs/progress.md`。
- 重要发现写 `docs/debug_log.md`。
- 目标：给出新的 `CoreMark/MHz` 与 CPI，并明确回答"还能再压多少、卡在哪"。

---

## 4. 环境与工具链（照抄，不要猜、不要重新探测）

| 项 | 值 |
|---|---|
| 权威仓库 | `D:\RISC_V_CPU_2026` |
| PowerShell | 本机默认只有 Windows PowerShell 5.1。发布/PDS/回归脚本必须用 `C:\Users\xwc\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`（7.6.5） |
| Python | `D:\Python313\python.exe`（含 pyserial）。**PATH 里的 `python` 是豆包沙箱运行时，没有 pyserial，禁止使用** |
| PDS | `D:\Pango\PDS_2024.2-SP2`（综合 `bin\pds_shell.exe`、下载 `bin\cdt_cfg.exe`、JTAG 服务 `bin\cdt_js.exe`） |
| License | `D:\Downloads\new_pds_60452e195a32.lic`（设 `PANGO_LICENSE_FILE`） |
| 仿真器 | Icarus Verilog 12：`D:\Tools\iverilog-v12` |
| RISC-V 工具链 | `RISCV_PREFIX=riscv-none-elf-`，xPack GCC 15.2.0 |
| 开发板 | MES50HP，`PGL50H-6IFBG484`，系统时钟 **P20 = 50 MHz 固定晶振** |
| UART | RX=`R8`、TX=`R9`，115200 8N1，串口 **COM11**（CP210x） |
| **JTAG 下载（现已可用）** | 先 `Start-Process 'D:\Pango\PDS_2024.2-SP2\bin\cdt_js.exe' -ArgumentList '-work_dir','D:\RISC_V_CPU_2026\tmp','-port','65420'`；再用 `cdt_cfg.exe -file <tcl> -work_dir D:\RISC_V_CPU_2026\tmp`。TCL 内容：`cfg_connect -ip 127.0.0.1 -port 65420` / `cfg_scan_chain` / `cfg_assign_file -file <sbit> -device_index 0` / `cfg_program -device_index 0` / `cfg_disconnect`。成功后打印 `The done bit is 1` |
| 扫描链 | `Cable index 0: USB Cable II`，器件 `PGL50H` |

### 常用命令（复制即用）

```powershell
$pwsh7 = 'C:\Users\xwc\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe'

# 全套回归（每次 RTL 改动后必跑）
& $pwsh7 -NoProfile -File scripts\run_final_regression.ps1 -Quick

# CoreMark RTL 仿真（Predictor On / Off）
& $pwsh7 -NoProfile -File scripts\run_coremark_pipeline_tb.ps1
& $pwsh7 -NoProfile -File scripts\run_coremark_pipeline_tb.ps1 -DisablePredictor

# 重新生成 50 MHz 镜像（关键：PERF_WINDOW_ALIGN=1 才让计数器与 ticks 同口径）
& $pwsh7 -NoProfile -File scripts\generate_coremark_fpga_memory.ps1 -Iterations 1000 -ClockHz 50000000 -AutoStart 0 -PerfWindowAlign 1

# 重建 50 MHz 位流
& $pwsh7 -NoProfile -Command "cd fpga\coremark; & 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name coremark_generated"

# 下载 + 采集（约 40 秒）
& 'D:\Pango\PDS_2024.2-SP2\bin\cdt_cfg.exe' -file tmp\program_coremark_wa.tcl -work_dir D:\RISC_V_CPU_2026\tmp
D:\Python313\python.exe python\coremark_serial.py COM11 --clock-hz 50000000 --timeout 200 `
  --output release\evidence\coremark_uart_opt50m_aligned.log `
  --summary release\evidence\coremark_board_opt50m_aligned.json

# CPI 归因报告
D:\Python313\python.exe python\coremark_cpi_analysis.py --board release/evidence/coremark_board_opt50m_aligned.json
```

---

## 5. 绝对不能破坏的东西

- **Core/SoC 边界**（`docs/interfaces.md`）：Core 只通过统一取指/数据访问/提交事件接口对外；
  不得引入设备专用地址、片选、状态机。
- **接口与模块名**：`pipeline_cpu` 的端口不得改（含 `trace_*`、`i_req_*`/`i_rsp_*`、`d_req_*`/`d_rsp_*`、
  `event_*`）。改动必须是内部时序，不是接口。
- **提交级 trace 语义**：`trace_valid` 必须仍表示"一条指令架构提交"，
  空泡/被 Flush 的指令不得产生提交事件。
- **Reference Model 等价性**：Task 17/24 的 Single Cycle ↔ Pipeline 最终状态与提交 trace 必须继续 PASS。
- **`release/` 发布包**：不要删除或直接覆盖。`release/final_submission/SHA256SUMS.txt` 等清单会因此失效。
  如需更新，必须按顺序走 `scripts\export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1`，且必须用 pwsh 7。
- **`PERF_WINDOW_ALIGN=1` 是板级 CPI 归因的前置条件**：不加它，`COREMARK_READY` 的 UART 轮询等待
  会进入计数窗口，产生 `stall > cycles` 的失真数据。历史 `release/evidence/coremark_board.json`
  就是这种失真数据，只有 `ticks`/`score` 字段有效。
- **已 PASS 的 Regression**：不得无理由修改其被测行为。
- **保留用户与前一个 Agent 的已有改动**，不擅自回退、不覆盖无关工作。

---

## 6. 当前基线指纹（用于 Before/After 可比性）

| 项 | 值 |
|---|---|
| git commit | `b4760bd`（RTL 优化为 `284f736`） |
| `rtl/perf_monitor.v` SHA-256（前 16） | `B9A41F8D23956422` |
| `rtl/pipeline_cpu.v` SHA-256（前 16） | `8E8EB3A69B2EF45E` ← **本次很可能要改的就是它** |
| 50 MHz CoreMark 位流 SHA-256 | `8001A60D4CB17433E8226452EA8A255B144F64529245EE7F3A706F3144110A8A` |
| 80 MHz PLL CoreMark 位流 SHA-256 | `FF6775A465A5CB68C99FCDFE57275B93C2B809D3D260D68D64CC31D967355F70` |
| 50 MHz 逻辑分析仪位流 SHA-256 | `DB705898A42BA25628303017034DDB7531DBA44BDBB58574E5CAFC19AAA331E6` |
| 80 MHz PLL 逻辑分析仪位流 SHA-256 | `261D3989AC2D3EC686B9C740B42E988A96175B8534BE5F494D66573A1A54D898` |

> **提醒**：`rtl/pipeline_cpu.v` 一改，上面四个位流全部失效，必须重建 + 重新上板实测（至少 CoreMark 两个配置）。

---

## 7. 必读文档

1. `docs/coremark_cpi_analysis.md` —— CPI 归因（本次任务的起点）
2. `docs/performance_tuning.md` —— 频率/资源/关键路径全套数据，以及 80 MHz PLL 方案
3. `docs/rtl_changes.md` —— 上一轮改动记录与**未做的候选清单**（含访存候选的详细分析）
4. `docs/interfaces.md` —— Core/SoC 边界与端口契约（改 Core 前必读）
5. `docs/architecture.md` —— 流水线级字段、Bubble、MEM 等待、redirect 时序约定
6. `docs/progress.md` —— 当前 Gate 与已知问题

---

## 8. 验收要求

- 每次 RTL 改动后 `scripts\run_final_regression.ps1 -Quick` 必须 PASS。未通过不得宣称完成。
- 任何"提升"结论必须同时给出 Before/After，且 **After 必须是实体板实测**；RTL 仿真只能作辅助证据。
- CoreMark 必须官方四 CRC 全过 + `Correct operation validated.` + 运行 ≥10 秒，否则该数据无效。
- 时序必须 `All Constraints Met`，否则该位流不得下载到板子上运行。
- 若最终 CPI 没有明显改善，**如实报告"没有改善"以及卡在哪里**，不许用仿真数字冒充板上成绩。
- 每轮结束更新 `docs/progress.md`，重要发现写入对应文档。

---

## 9. 最终回复格式要求

按 `AGENTS.local.md` 给可接班摘要：修改文件、验证命令与结果、已知风险、下一步、是否满足验收条件。
**数据要具体到数字**（CPI、CoreMark/MHz、Score、cycles、stall、flush 的 Before → After），
不要只写"已优化"。并明确说明实体板复测是否完成。
