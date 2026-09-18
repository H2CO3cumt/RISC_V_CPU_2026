# 新会话执行指令（把本文件全文粘贴给新会话即可）

> 项目规则 `AGENTS.md` / `AGENTS.local.md` 会自动加载，无需重复。以下是增量信息与本次任务的明确授权。

---

## 0. 授权声明（覆盖 AGENTS.md 2.1 的默认限制）

**用户已明确授权直接修改 RTL。** 本任务中你可以编辑、新增、替换 `rtl/` 下的 Verilog 源文件（含 `pipeline_cpu.v`、`alu.v`、`branch_predictor.v`、`perf_monitor.v` 等），不必只提供模板让用户手写。但仍必须遵守：

- 修改前说明依据与预期影响，修改后报告验证结果。
- 保持最小、可审查的改动，一次只动一块，不顺手大重构。
- 不改模块名与已确定端口，除非有明确理由并在文档中记录。
- 不把外设专用逻辑塞进 CPU Core（边界见 `docs/interfaces.md`）。
- 每次 RTL 改动后必须重跑回归。

---

## 1. 总体目标

**在赛题一的评分规则范围内，把数据做到最好**，并对最终版完成交付：更新桌面快捷方式、给出变更说明文档。

用户希望上 70 MHz（并提到此前约束到 80–85 MHz 曾可达）。**请先读第 3 节与第 3.5 节，方向别搞错。**

---

## 2. 评分标准（赛题指南原文，已核对 PDF 原页）

性能评分基于 CoreMark v1.0 跑分结果：

```
Score = CoreMark_Iterations / (Total_Time × Frequency)
```

性能指标三项：
1. **执行效率**：比较 CoreMark/MHz。分值越高，代表流水线设计越优化。
2. **时钟频率**：在满足时钟约束的前提下，处理器能达到的最高工作频率。
3. **资源效率**：计算 CoreMark / LUTs。

其他计分项：
- 应用场景构建：模型的整体资源、时序、主频。
- 技术实现与文档：代码规范（模块化、时序约束合理性、注释完整性）；**分析报告需用 ILA 抓取的波形图分析 CPU 执行 CoreMark 关键算法时的流水线效率**。

硬性要求：CoreMark 测试必须设置迭代次数使运行时间**不低于 10 秒**。

---

## 3. 战略判断（关键，先想清楚再动手）

**Score 公式的分母里有 Frequency，所以它等于 CoreMark/MHz，是频率归一化的。**

实测验证：`1000 ÷ (33.829 s × 50 MHz) = 0.5912`，与板上打印的 `CoreMark/MHz x1000 : 591` 完全一致。

结论：

- **单纯提高主频不会提高 Score**（分子分母同比例变化）。要提 Score 必须**降低 CPI**。
- **提主频服务于独立的第 (2) 项「时钟频率」**，这一项同样是 P0 计分项，必须做。
- 两条线都要推进，但**收益来源不同**：CPI → 第 (1) 项；Fmax → 第 (2) 项；面积 → 第 (3) 项。
- **提频率可能反过来伤 Score**：为满足时序而插流水级/简化逻辑可能让 CPI 变差。所以必须给出**帕累托数据**（频率、CoreMark/MHz、LUT 三者同看），不能单点最优化。

## 3.5 重要修正：松约束下「估算 Fmax」只是下界，不是天花板

**这条是本任务最大的机会点，必须先验证。**

PDS 的 `Estimated Frequency` 是在**给定约束下**完成布局布线后反推的。约束松（20 ns / 50 MHz）时工具没有动力去优化关键路径，所以报出的值**低于真实能力**。同一套 RTL、不同配置在同一松约束下差了一大截，正好证明这一点：

| 配置 | 50 MHz 松约束下的估算 Fmax | Slack | 逻辑级数（最差路径） |
|---|---|---|---|
| `pipeline_soc` | **71.7463 MHz** | +6.062 | — |
| `coremark_ila` | **68.7427 MHz** | +5.453 | — |
| `logic_analyzer` | 57.6735 MHz | +2.661 | 25 |
| **`coremark`（计分用）** | **54.9602 MHz** | +1.805 | **26** |

**用户称此前把约束设到 80–85 MHz 区间并且能过。仓库内没有任何记录支持或否定这条**——全部 `.fdc` 都是 `-period {20.000}`，git 历史里也没有更紧的约束版本。

**因此必须把「紧约束验证」作为第一项任务（T0）**：不花在 RTL 上，只改约束重跑，成本极低，收益可能是第 (2) 项最大的一次跃升。

同时在 **80–85 MHz 实跑上板**需要 PLL 倍频（P20 是 50 MHz 固定晶振），见 T5。

---

## 4. 当前基线数据（已实测，直接引用，不要重测）

### 4.1 板级 CoreMark 实测（50 MHz，1000 次迭代，task28 配置）

| 字段 | 值 |
|---|---|
| CoreMark 分数 | **29.559**（`score_x1000 = 29559`） |
| CoreMark/MHz | **0.591**（`coremark_per_mhz_x1000 = 591`） |
| iterations | 1000 |
| Total ticks | 1,691,496,677 |
| 运行秒数 | 33.829（≥10 s 达标） |
| CPI | 2.271 |
| 官方校验 | crclist 0xe714 / crcmatrix 0x1fd7 / crcstate 0x8e3a / crcfinal 0xd340，`Correct operation validated.` → PASS |

七项性能计数器（同一轮实测）：

| 计数器 | 值 |
|---|---|
| cycles | 2,078,613,829 |
| instret | 914,907,729 |
| stalls | 140,999,631 |
| load_stalls | 7,151,182 |
| branches | 262,616,640 |
| taken | 187,441,461 |
| flushes | 74,615,337 |

> 口径差异：`cycles`（2.079e9）覆盖范围比 `ticks`（1.691e9）大，CPI 2.271 来自 `cycles/instret`，而 Score 用的是 `ticks`。做归因分析时先把口径对齐，别混用。

日志与 JSON：`release/evidence/coremark_uart.log`、`release/evidence/coremark_board.json`

CoreMark 位流 SHA-256：`92638DAF8C73F63214CB1C42DEBC17B8E4B7E4FAF42C1C132084F022EDABF5A7`
（桌面 `coremark_btb.sbit` 是它的备份，**作为 50 MHz 基线保留，不要删**）

### 4.2 coremark 的关键路径（计分配置，最差路径）

- 起点 `core/rf/regs/iGopDrm/CLKB` → 终点 `perf/flush_count[62]/opit_0_A2Q21/CE`
- **26 级逻辑**，arrival 22.789 ns，slack +1.805 ns
- 第二差：同起点 → `perf/flush_count[63]`，26 级，arrival 22.789，slack +1.805
- 第三差：同起点 → `perf/flush_count[58]`，25 级，arrival 22.605，slack +1.989
- **最差三条全部终点在 `perf/flush_count`**
- 最差 hold：`core/ifid_pc[0]` → `core/idex_pc[0]`，arrival 5.534，slack +0.276，**0 级逻辑（纯走线）**

### 4.3 logic_analyzer 的关键路径（对照，同一瓶颈）

- 起点 `core/rf/regs/iGopDrm/CLKB` → 终点 `perf/flush_count[62]/.../CE`
- 25 级逻辑，arrival 21.933，required 24.594，slack +2.661
- **逻辑延迟 8.660 ns（52.5%），走线延迟 7.846 ns（47.5%）**
- 构成：寄存器堆 DRM tco 2.351 → 转发/操作数选择 → exalu → exmem_alu→ex_result（fanout=18，走线 0.965）→ `N161.eq_0..eq_14`（**16 级进位链做相等比较**，约 1.0 ns）→ N164→perf_mispredict（fanout=7）→ N172→**perf_flush（fanout=46）** → flush_count[24..60] **10 级 CECO 进位链**（约 1.84 ns）

### 4.4 结论：所有配置的公共瓶颈都是性能计数器

**`perf_flush` / `perf_mispredict` 是纯统计信号，不参与任何架构状态。** 把 flush/mispredict 的累加打一拍（流水化统计），可砍掉路径尾部的比较链 + 计数器进位链（约 2.5–3.4 ns 量级），而 CoreMark 计数只差 ±1，对分数无影响。

**这是第一优先级的 RTL 改动**：一次改动同时提升 task28（计分用）、task30（应用场景）两个配置的 Fmax，风险低、收益直接。

### 4.5 RTL 仿真基线（Before/After 参照）

| 配置 | cycles | retired | CPI | BTB hit | mispredict |
|---|---:|---:|---:|---:|---:|
| Predictor Off | 2,106,042 | 775,901 | 2.7143 | 0 | 131,903 |
| Predictor On | 1,852,156 | 779,952 | 2.3747 | 203,492 | 51,908 |

BTB 减少 cycles 12.06%；共 213,756 条条件分支，BTB 命中率约 95.20%，方向+目标综合正确率约 75.72%。
无 BTB 时 RTL 仿真 CoreMark/MHz = 0.520000。

---

## 5. 环境与工具链（照抄，不要猜、不要重新探测）

| 项 | 值 |
|---|---|
| 权威仓库 | `D:\RISC_V_CPU_2026` |
| PowerShell | 本机默认只有 **Windows PowerShell 5.1**。发布/PDS 脚本必须用 `C:\Users\xwc\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe`（7.6.5） |
| Python | `D:\Python313\python.exe`（含 pyserial 3.5）。**PATH 里的 `python` 是豆包沙箱运行时，没有 pyserial，禁止使用** |
| PDS | `D:\Pango\PDS_2024.2-SP2`（综合：`bin\pds_shell.exe`；下载：`bin\cdt_cfg.exe`；JTAG 服务：`bin\cdt_js.exe`） |
| License | `D:\Downloads\new_pds_60452e195a32.lic` |
| RISC-V 工具链 | `RISCV_PREFIX=riscv-none-elf-`，xPack GCC 15.2.0 |
| 开发板 | MES50HP，PGL50H-6IFBG484 |
| 系统时钟 | **P20 = 50 MHz 固定晶振**（不是可编程时钟） |
| UART | RX=`R8`、TX=`R9`，115200 8N1 无流控 |
| 串口设备 | `COM11`（Silicon Labs CP210x USB to UART Bridge） |
| JTAG 下载 | 需 `cdt_js.exe` 在 `127.0.0.1:65420` 监听；下载用 `cdt_cfg.exe -file <tcl> -work_dir <dir>`，TCL 模板见 `tmp\program_coremark.tcl` |

常用入口：

```powershell
# CoreMark 重建（1000 迭代 + BTB，约 2 分钟）
& '<pwsh7>' -NoProfile -File scripts\run_coremark_pds.ps1

# 全套回归（提交前必跑）
& '<pwsh7>' -NoProfile -File scripts\run_final_regression.ps1 -Quick

# 板级 CoreMark 采集（约 40 秒）
D:\Python313\python.exe python\coremark_serial.py COM11 `
  --output release\evidence\coremark_uart.log `
  --summary release\evidence\coremark_board.json
```

---

## 6. 任务清单

### T0. 紧约束验证（**最先做**，成本最低、可能收益最大）
不改任何 RTL，只改 `.fdc` 的 `create_clock -period`，对 **50 / 60 / 70 / 75 / 80 / 85 MHz** 各跑一次完整综合-布局布线-时序流程（对应周期 20 / 16.667 / 14.286 / 13.333 / 12.5 / 11.765 ns，waveform 取周期的半值）。

目的：验证用户"80–85 MHz 可达"的说法，确定松约束下的真实天花板。

**必须用隔离的临时目录**（例如 `tmp\fmax_sweep\fpga\coremark\` 配合 `tmp\fmax_sweep\rtl\`，让 recipe 里的 `../../rtl` 正确解析），**不要污染 `fpga\coremark\` 的正式产物与位流**。

若高频率下有 failing endpoints，逐点记录失败路径，得到"还差多少 ns"的精确 gap。

### T1. CPI 分解与瓶颈归因
用第 4.1 节七项计数器 + RTL 仿真（`scripts/run_coremark_pipeline_tb.ps1`）做归因，输出：
- stall 占 cycles 比例、load-use 占 stall 比例、flush 占 cycles 比例
- 分支预测正确率、mispredict 造成的 flush 次数
- 实际 CPI 与"无停顿理想 CPI"的差距，**落到"哪一类事件贡献了多少 CPI"**

不得只给比率，必须给出可行动的结论。

### T2. 关键路径批量提取
从 `report_timing\*.rtr` 提取最差 10 条路径（起点/终点/逻辑级数/逻辑 vs 走线延迟占比），标注：
- 哪些属于 CPU Core，哪些属于 `perf` 计数器（后者可安全打拍）
- 每条路径的可流水化点

### T3. RTL 优化（循环推进，一轮一块）
候选按预期收益排序，**每个候选都必须先由 T0/T1/T2 的数据证实，不许凭感觉改**：

1. **perf 计数器累加流水化** —— 砍掉 `perf_flush` fanout=46 与 10 级 CECO 进位链（见 4.2/4.3/4.4）。**第一优先。**
2. **相等比较链 `N161.eq_*`（16 级进位链）** —— 改为树形比较或提前产生
3. **寄存器堆读出 → 转发 → ALU 路径** —— 重新分级，缩短组合深度
4. **分支预测器索引/比较逻辑** —— 降 fanout、缩短关键路径
5. **load-use / 冒险控制路径** —— 结合 T1 的 stall 归因
6. **hold 路径**（`ifid_pc→idex_pc` 无逻辑、纯走线）—— 必要时用 PDS 的 hold fix 或局部加缓冲，别为它牺牲 setup

每轮必须按此顺序：
```
记录 Before（WNS/Fmax/LUT/FF/CPI/CoreMark）
→ 单点最小改动
→ 重新综合出时序
→ 重跑 scripts\run_final_regression.ps1 -Quick（必须 PASS）
→ 重新下载位流并板级实测 CoreMark（必须 CRC 全过、≥10 s）
→ 记录 After
```
一轮只动一块，单独给出 Before/After。**不允许"改了好几处然后宣称整体提升"。**

### T4. 优化后重跑频率扫描
用 T3 优化后的 RTL 重跑 T0 的频率点，确认新的天花板，并找出**综合总分最优**的频率点（不一定是最高频率点）。

### T5. 板级高频验证（仅在时序通过后做）
P20 是 50 MHz 固定晶振，实跑 >50 MHz **必须加 PLL 倍频**（PGL50H 有 5 个 PLL，50×7/5=70、50×8/5=80）。要求：
- PLL 例化放在 Core 外（board wrapper 内），不得进入 CPU Core
- 新增 PLL IP 后必须重新完整做时序与上板验证，不能沿用旧结论
- 记录 PLL 配置、资源开销、新的时钟约束
- UART 波特率分频要跟着新时钟重算，否则串口输出会乱码

### T6. 数据汇总
写入 `docs/performance_tuning.md`，包含：
- 频率 × (WNS / TNS / WHS / THS / 是否 All Met / 估算 Fmax / LUT / FF / DRM / CoreMark / Score / CPI / CoreMark per LUT) 完整表
- 每轮 RTL 改动的 Before/After
- 元数据：git commit、`.fdc` 哈希、bitstream SHA-256
- 同时更新 `docs/progress.md`

---

## 7. 每个频率点必须记录的数据

**A. 时序闭合（决定这个频率算不算分）**
约束周期/目标频率、setup WNS、TNS 与失败端点数（必须 0）、hold WHS、THS（必须 0）、是否 `All Constraints Met`、估算 Fmax（=1/(周期−WNS)）、报告文件路径与生成时间

**B. 资源（对应第 3 项）**
LUT / FF / DRM18K，**必须注明阶段（综合统计 vs 布局布线后），两个阶段不得混用**；CoreMark/LUTs

**C. CoreMark 实测（对应第 1 项）**
score_x1000、ticks、iterations、实际秒数、CPI、四个官方 CRC + `Correct operation validated.`、七项性能计数器

**D. 关键路径**
最差路径起点/终点/逻辑级数、逻辑延迟 vs 走线延迟占比（每个频率点都要，因为路径会变）

**E. 可比性元数据**
源码 git commit / 文件哈希、`.fdc` 哈希、bitstream SHA-256、软件镜像一致性（iterations 都是 1000 且运行 ≥10 s）

---

## 8. 验收要求

- 每次 RTL 改动后 `scripts\run_final_regression.ps1 -Quick` 必须 PASS。未通过不得宣称完成，不得进入下一项。
- 任何"提升"结论必须同时给出 Before/After，且 **After 必须是实体板实测**；RTL 仿真只能作辅助证据。
- CoreMark 必须官方 CRC 全过 + `Correct operation validated.` + 运行 ≥10 秒，否则该数据无效。
- 时序必须 `All Constraints Met`，"估算 Fmax 高于目标频率"才可以宣称该频率可用。
- 时序不过的频率**不计入得分**，且不得下载到板子上运行（超频不可靠）。

---

## 9. 绝对不能破坏的东西

- **Core/SoC 边界**（`docs/interfaces.md`）：Core 只通过统一取指/数据访问/提交事件接口对外；不得引入设备专用地址、片选、状态机。
- **`release/` 发布包**：不要删除或直接覆盖。`release/final_submission/SHA256SUMS.txt` 等清单会因此失效。如需更新，必须按顺序走 `scripts\export_final_submission.ps1` → `scripts\create_release_manifest.ps1` → `scripts\audit_release_package.ps1`，且必须用 pwsh 7。
- **桌面 `coremark_btb.sbit`**：50 MHz 基线位流，保留不要动（收尾时改名为 `coremark_baseline_50m.sbit` 存档）。
- **模块名与已确定端口**：不改，除非有明确理由并记录。
- **已 PASS 的 Regression**：不得无理由修改其被测行为。
- 保留用户与前一个 Agent 的已有改动，不擅自回退、不覆盖无关工作。

---

## 10. 收尾交付：替换桌面入口 + 变更文档（**必做，用户明确要求**）

全部优化与验证完成后，**必须**完成以下两件交付。

### 10.1 替换桌面上旧的快捷入口

桌面上现有这些是**旧版**，收尾时必须替换成指向新产物的入口（先把新入口建好并验证，再删旧的；命名沿用数字前缀便于排序）：

| 现有入口 | 收尾时替换为 |
|---|---|
| `1_FPGA工程_最新.lnk` → `fpga\logic_analyzer\logic_analyzer_generated.pds` | 指向**优化后**的逻辑分析仪工程 `.pds` |
| `2_最终位流_下载用.lnk` → 逻辑分析仪位流 | 指向**优化后**的逻辑分析仪 `.sbit` |
| 桌面散落的 `coremark_btb.sbit` | 换成**优化后**的 CoreMark 位流（旧的改名 `coremark_baseline_50m.sbit` 存档） |
| `8_测CoreMark分数.cmd` | 保留（自动找 COM11、自动算分），确认仍可用 |
| `3_逻辑分析仪上位机.lnk`、`4_逻辑分析仪使用说明.lnk`、`5_采集波形_80组VCD.lnk`、`6_最终交付包.lnk`、`7_项目仓库.lnk`、`11_新会话指令.md.lnk` | 路径不变则保留；包内容更新则同步刷新 |

要求：
- 快捷方式必须指向**真实文件**，不是副本；目标文件必须存在且已验证。
- **注意 PDS 工程的相对引用**：`logic_analyzer_generated.pds` 用 `../../rtl/*.v` 引用源码，目录层级不能动，否则会静默接到错误的源码（项目里踩过一次）。
- 新增 `12_性能调优记录.lnk` 指向 `docs\performance_tuning.md`。
- 删除旧入口前先确认新入口可用。

### 10.2 变更说明文档

新建 `docs\rtl_changes.md`（或并入 `performance_tuning.md` 的一个章节），**逐个改动**说明：

| 必填字段 | 说明 |
|---|---|
| 改动文件 | 精确到文件名 |
| 改动位置 | 模块 / 信号 / 行号 |
| 改动前是什么 | 关键代码或逻辑描述 |
| 改成什么 | 关键代码或逻辑描述 |
| **为什么改** | 依据哪条关键路径 / 哪个计数器归因（引用具体数据） |
| 量化收益 | Fmax / WNS / LUT / FF / CPI / CoreMark 的 Before → After |
| 对架构的影响 | 是否触及 Core/SoC 边界、接口、Reference Model |
| 验证方式 | 跑了哪些 Regression、板级实测结果 |
| 风险 | 残留影响、未覆盖项 |

并给出**总表**：

```
版本          | 目标频率 | All Met | Fmax | LUT | FF | DRM | CoreMark | Score(CoreMark/MHz) | CPI | CoreMark/LUT
基线(50MHz)   |          |         |      |     |    |     |          |                     |     |
优化后(...)   |          |         |      |     |    |     |          |                     |     |
```

最后必须明确回答：**是否达到 70 MHz？是否达到 80–85 MHz？** 若未达到，说清卡在哪条路径、还差多少 ns、下一步建议。

---

## 11. 交付物清单

1. 改动后的 RTL —— 每个改动文件 + 原因 + Before/After
2. `docs\performance_tuning.md` —— 完整频率-性能-资源数据表与关键路径分析
3. `docs\rtl_changes.md` —— 变更说明（改了哪里、为什么改、量化收益）
4. 更新后的 `docs\progress.md`
5. 新位流 + 板级 CoreMark 实测日志（`release\evidence\`）
6. **更新后的桌面快捷方式**（见 10.1）

---

## 12. 最终回复格式要求

按 `AGENTS.local.md` 给出可接班的摘要：修改文件、验证命令与结果、已知风险、下一步、是否满足当前验收条件。数据要具体到数字，不要只写"已优化"。并明确列出桌面入口的最终状态。
