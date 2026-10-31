# Project Progress

> 最后更新：2026-10-30（**上位机收口为一个 py 文件**：用户明确要求"一个 py 文件实现所有功能"。
> 唯一用户入口改为仓库根目录 `逻辑分析仪演示.py`（单文件、自包含，只依赖 pyserial），
> 本日补齐 13 条 trace 判据 + 示例/实时来源标识，并把内置样例换成与当前固件同源的 100 条实板记录；
> 根目录 `pyUI.py` 退化为跳板，`python/start_logic_analyzer*.cmd` 改为拉起单文件。
> 多文件那套（`python/mes50hp_validation_ui.py` + 5 模块）只保留为回归被测对象，**不再是入口**。
> 详见文末 2026-10-30 章节。）
> 上一版：2026-10-28（**第 ② 页离线回放与交付包收口**：修掉"热力图看起来是写死的"
> ——样本换成与当前 trace85 镜像同源的那一枪（15/15 PASS）、回放判据改用打点值当输入、
> 第 ② 页加「离线回放」徽标、真采集/离线拆成两个入口；交付包 10-14 之后首次重跑导出链：
> `EXPORT PASS files=315` → `MANIFEST PASS files=4092` → `AUDIT PASS final_files=316`。
> 不改任何 RTL、不改 `pipeline_cpu.v`、不重打位流。详见文末 2026-10-28 章节。）
> 上一版：2026-10-28（**提交代码包与用语清理**：桌面生成
> `RISC-V_CPU_2026_提交代码_20261028.zip`（2,440 个文件 / 8.54 MB），只含代码；
> 72 个源码与脚本文件里的过程性黑话已清理，RTL 只动注释；包内按 23 条词表复扫 0 命中，
> 解压后直接跑回归全 PASS。详见文末 2026-10-28 章节。）
> 上一版：2026-10-21（**提交级 trace 可视化（进行中）**：Core 外部的 trace 缓冲 +
   MMIO 从端口 + 固件 0xAA 命令 + 单页数据流可视化；模块级与上位机判据全 PASS、
   **PDS `All Constraints Met`**；SoC 端到端仿真场景 2 还差一个 TB 缓冲参数，
   **实板验证被"JTAG 下载线未被系统识别"阻塞**。详见文末 2026-10-21 章节。
   本轮**未改动** `pipeline_cpu.v` 与交付位流 la85）
> 上一版：2026-10-19（**M 扩展乘法并行部分积**：`rtl/mdu.v` 的 `MUL_LAT` 3 → 2 并成为默认，
> **实板 Score 193.192 → 197.408（+2.183%）**、CoreMark/MHz 2.272 → 2.322、ticks −2.135%，
> LUT −46、85 MHz 时序仍 Met；24 项回归全 PASS。交付 la85 位流未重打）
> 状态依据：`AGENTS.md`、`docs/competition_scoring.md`、`docs/roadmap.md`、`docs/architecture.md`、`docs/interfaces.md`、`docs/fpga_platform.md`、`docs/application_logic_analyzer.md` 与当前项目文件。聊天记录不作为任务完成证明。

## M 扩展（RV32IM）与采集源双源可选（2026-10-14，用户批准的范围变更）

两项都是"只回答问题"之后的**显式授权实施**：用户原话是"做 M 扩展和 J8 外部 / Core 内部
双源可选，我开发板已经同上电源了你可以直接连接开发板，不要留给我任何操作"。
范围契约已写进 `AGENTS.md` §1.7（ISA）与 `docs/application_logic_analyzer.md` §6.10（双源）。

### 1. 结论（实体板实测）

| 项 | 基线（RV32I） | **本次（RV32IM）** | 变化 |
|---|---:|---:|---:|
| CoreMark Score @50 MHz | 46.816 | **113.642** | **2.43×** |
| **CoreMark Score @85 MHz（与交付同频）** | **79.587**（`cm85r`，当前 RTL 同源点；归档 `cm85` 同值） | **193.192**（`cmim85`） | **2.43×** |
| **CoreMark/MHz** | **0.936** | **2.272** | **2.43×** |
| ticks / 迭代 | 1,068,007 | 439,975 | −58.8% |
| 指令数 / 迭代 | 778,037 | 362,131 | −53.5% |
| CPI | 1.494 | 1.550（50 MHz）/ 1.547（85 MHz） | +3.7% |
| 迭代次数 / 时长 | 1000 / 21.36 s | 2000 / 17.60 s（50 MHz）· 4000 / 20.70 s（85 MHz） | 均 ≥10 s ✓ |
| 官方 CRC | 全过 | **全过**（两个频点） | ✓ |
| **CoreMark/LUT（85 MHz 同源同频）** | **0.0190**（79.587÷4198） | **0.0460**（193.192÷4198） | **2.43×** |
| RTL 仿真 cycles（同 TB/程序） | 1,251,724 | 594,792 | −52.5% |

- **依据**：`third_party/coremark/core_matrix.c` 每迭代固定 10,575 次乘法，全部走 libgcc
  `__mulsi3`；反汇编实测循环体 6 条指令、平均 7.94 次迭代/次乘法；板级 ILA 窗口
  84.3% 的提交落在该循环里 ⇒ 约 **60% 的指令**花在软件乘法上（`docs/coremark_cpi_analysis.md` §5 的
  "取指已满速"之后剩下的最大单项）。
- **口径纪律**：`rv32i` 仍是默认与可比口径（历史成绩、交付镜像、`claims_map` 既有数字都不变），
  `rv32im` 是**并列的增强配置**。CoreMark 输出自带 `Compiler flags : -O2 -march=rv32im -mabi=ilp32`
  一行可自证；两个位流、两份证据文件分别留档。

### 2. 改了什么

| 层 | 文件 | 改动 |
|---|---|---|
| RTL 新增 | `rtl/mdu.v` | 乘除法单元：三段流水乘法（锁操作数 → 16×32 部分积寄存 → 移位相加 + 符号修正）+ 32 拍恢复余数法除法 |
| RTL | `rtl/decoder.v` | `mdu_en`/`mdu_op` 输出；`funct7=0000001` 整组由非法改为合法（两个 CPU 都启用，不受 `ENABLE_SYSTEM` 影响） |
| RTL | `rtl/pipeline_cpu.v` | ID/EX 的 mdu 位；`ex_result` 增加 mdu 分支；`mdu_block` 停顿 + `ack` 握手；**新增 `exmem_retired`** 让 MEM 级能与 EX 级解耦排空 |
| RTL | `rtl/single_cycle_cpu.v` | 同一套 M 扩展（Reference Model 必须同 ISA）+ `mdu_busy` 等待 |
| RTL | `rtl/logic_analyzer_mmio.v` | `probe_channels` 输入 + 寄存器 18（`src_sel`）；**采集源选择结果寄存一拍**再进引擎 |
| RTL | 四个板级顶层 | `core_probe`（8 根 Core 已有冻结输出）**再打一拍**后接探针 |
| 固件 | `software/logic_analyzer/logic_analyzer.c` | `LA_SRC` + **0xA8** 命令（16 字节：pre/post 各 16 位、[14]=采集源）；0xA5/0xA7 明确回写 `LA_SRC=0` |
| 上位机 | `python/logic_analyzer_serial.py`、`python/core_probe_board.py`、`python/test_logic_analyzer_serial.py` | `source`/`core` 模式/通道名/板级验收/5 项新单测 |
| 脚本 | `run_mdu_tb.ps1`、`run_pipeline_m_ext_tb.ps1`、`run_coremark_im_pds.ps1`、`run_core_probe_board.ps1`、`score_coremark_board.ps1`（新增 `cmim`）、`run_coremark_board.ps1`（输出路径可覆盖）、`program_board.ps1`（新增 `cmim`）、`check_coremark_elf.ps1`（双向 ISA 校验）、`generate_*.ps1`（MARCH/输出目录参数化）、46 个编译脚本 + 13 个 PDS 配方加入 `rtl/mdu.v` | |
| 工程 | `fpga/coremark_im/`（新增 RV32IM 计分工程） | |

### 3. 本轮修掉的三个真 bug（详见 `docs/debug_log.md`）

1. **背靠背除法共用上一次结果**（`rem` 返回了商）——状态机只认 `run` 的边沿；
   新增 `ack` 消费脉冲。
2. **CoreMark rv32im 整机死锁**（停在一条 `lbu`）——访存"完成"由握手定义，
   而 MEM→WB 原来与"ID/EX 换入 EX/MEM"同拍原子发生；除法停顿把两者拆开后
   `mem_block` 永久为 1。新增 `exmem_retired` 退休标记。
3. **乘法器进关键路径**：一拍组合 32×32 被综合成 4 级串联 APM，
   50 MHz WNS 掉到 +0.234 ns、85 MHz 违例 −3.268 ns。改两段流水后
   50 MHz +1.841 ns、85 MHz `All Constraints Met`。

### 4. 逻辑分析仪：采集源双源可选

- **外设没换**：官方指南 `tmp/pdfs/competition_guide.txt` 第 210～212 行把"逻辑分析仪"
  与游戏机、工控机并列写进"应用场景构建"示例。本次改的是**被测对象**。
- 8 根探针 + MMIO 寄存器 18 切换（**不重新综合**）+ 0xA8 命令；判据是
  "窗口里既有 ch7 提交脉冲又有 ch0 取指请求"（只查点数会放过"采到一整窗 0"）。
- **实板实测**（`release/evidence/core_probe_board/`，flush / stall 两组触发各 3 次全 PASS）：
  2048 点全速窗口里 **1187 条提交 / 1987 拍 ⇒ 窗口 IPC ≈0.597**，其中 **785 拍是停顿（39.5%）**，
  窗口内 4 次控制流冲刷——这正是"用自研仪器量自研 CPU"的第一组真实读数。

#### 4.1 RV32IM 85 MHz 计分点（2026-10-14 追加，用户要求补齐）

用户问"带 M 扩展的为啥只有 50M"，查下来是**没建过**而不是跑不了：`fpga/coremark_im` 的
`.fdc` 写死 `create_clock clk_50m -period 20.000`（50 MHz、无 PLL），而 80/85/90 MHz 的计分工程
都建在 M 扩展之前、从未用新 RTL 重建（资源报告里 `APM = 0`，没有乘法器）。本轮补齐：

| 项 | 值 |
|---|---|
| 工程 | `fpga/coremark_im_85m`（源文件取自 `fpga/coremark_85m`：同一颗 `pll_85m` + 同一个顶层；**只把镜像换成 `-march=rv32im`**，4000 迭代） |
| 构建入口 | `scripts/run_coremark_im_85m_pds.ps1 -Iterations 4000` |
| 位流 | `EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1`，**`All Constraints Met`**，85.0000 MHz 请求 / **86.8456 MHz** 估算，WNS **+0.250 ns**，**4198 LUT / 3361 FF** |
| 实体板 | **Score 193.192、CoreMark/MHz 2.272、ticks 1,759,901,953、20.704 s、官方 CRC 全过**（`Compiler flags : -O2 -march=rv32im -mabi=ilp32` 自证），CPI 1.547 / IPC 0.646 / 停顿占 27.1% / 冲刷 2.07% |
| 证据 | `release/evidence/coremark_board_cmim85_20261014.json` + `coremark_uart_cmim85_20261014.log`；`claims_map.md` §3.1c |
| ISA 自证 | `scripts/check_coremark_elf.ps1 -ExpectArch rv32im2p1` → `rv32i2p1_m2p0_zmmul1p0 ELF with 48 hardware M instructions` |
| 交叉校验 | 两个频点的 **ticks/迭代都是 439,975 拍**（逐位一致）、CoreMark/MHz 都是 2.272 ⇒ 同一份负载，Score 随频率线性 |
| **同源对照点 `cm85r`** | 用**与 cmim85 完全相同的源码**重建的 rv32i 位流：`EC71AFDD…`，LUT/FF/WNS 与 cmim85 **逐项相同**（4198 / 3361 / +0.250 ns），实体板 Score **79.587**、ticks **2,670,014,377**（与 09-30 归档 cm85 **逐位相同**）⇒ ① M 扩展不扰动 RV32I；② 同源同频 CoreMark/LUT 0.0190 → 0.0460（**2.43×**，旧稿的 2.11× 是跨 RTL 修订比较，已更正） |
| 上板入口 | `program_board.ps1 -Config cmim85` / `cm85r`；一键跑分 `score_coremark_board.ps1 -Config cmim85` / `cm85r` |

**为什么以前选 50 MHz 做对照**：Before/After 要在**同一频率**上比（46.816 vs 113.642 都是 50 MHz），
这样 2.43× 完全来自 ISA 与微架构、不掺频率变化；而 Score 本身是频率归一化的，
所以 50 MHz 点已经能证明 `CoreMark/MHz = 2.272`。85 MHz 这一点补的是**与交付同频的原始 Score**
与资源效率（同源同频 CoreMark/LUT **2.43×**），不是新的效率结论。

**顺带纠正一个会误导人的口径**：50 MHz 工程的"估算 Fmax ≈55–58 MHz"是**目标频率造成的假象**——
那两颗的最差路径终点是 `imem/mem_5/RSTA[0]`、`core/ifid_inst[14]/RS` 这类**复位端**，
PDS 在 50 MHz 目标下不去优化它；rv32i 的真实板级上界是实测的 **90 MHz**（cm90），
带 M 的 CoreMark 配置在 85 MHz 下收敛 +0.250 ns。**不能拿 55 MHz 说"M 扩展只能跑 50M"。**

#### 4.2 采集源必须能在界面上切（2026-10-14 补做，用户指出）

功能原来只做在 RTL、固件与库里：命令行能跑，**两个界面上都点不出来**，现场演示等于用不上。
用户指出后补做，并把两个上位机都当作交付面：

| 层 | 文件 | 改动 |
|---|---|---|
| 库 | `python/logic_analyzer_serial.py` | 新增 `capture_view(mode, source)`；判据/波形页标注/汇总改按 **view** 选；超时报错写清"触发通道上要有信号"，若**一个字节都没收到**则直接提示"固件停在等待采集完成，按 REST 或重下位流" |
| pyUI | `python/mes50hp_validation_ui.py` | 面板加「采集源」下拉框；切源自动把窗口换成新源下的合法默认值；波形标题写明真实源 |
| 单文件 | `逻辑分析仪演示.py` | 同一套下拉框 + `capture_view` 复制品；Core 源下读数区改报提交/停顿/冲刷/窗口 IPC，通道名跟着源走 |
| 单文件（2026-10-14 晚，用户报"点 core 没反应"后修） | `逻辑分析仪演示.py` | ① 抽出唯一的 `packet_for_cfg()`：`capture()` 与 `log_packet()` 共用（原来写日志那份**漏传 `source`**，core 模式抛 `ValueError`，异常从 Tk `after` 回调窜出 ⇒ 轮询循环不再续期、界面静默冻死）；② `poll()` 兜住所有异常并把 traceback 打进日志面板、`after` 放进 `finally`；③ 运行中切模式改为"请求停止 + 收尾后按新模自动重开"，并新增 `running_mode` 让状态行写明正在采哪个模式；④ 报错文案补上"0 字节 ⇒ 按 REST 或重下 `la85`"三条排查 |
| 测试 | `test_logic_analyzer_serial.py`、`test_logic_analyzer_ui.py`、`test_logic_analyzer_singlefile.py`（新增） | **40 → 52 项**：5 项 `capture_view` 组合、pyUI 的"波形标题写明真实源"与"控件真的布局出来"、单文件演示器的 6 项界面级用例（控件接线、切源改窗口、**六模式共用一个 `packet_for_cfg()`**、**运行中切模式要停+自动重开**、view 口径） |

- **为什么必须按 view 而不是按模式判**：采集源改变 8 根线的物理含义。改之前两种组合是
  **采集对、解释错的假失败**，实板都复现过：uart 模式 + Core 源被按 UART 帧解码而报
  `UART decode mismatch`；core 预设 + J8 源在波形页上把一根普通外部线标成 `trace_valid`。
  规则表见 `docs/application_logic_analyzer.md` §6.10.5。
- **实板证据**（真界面路径，不是重写的脚本）：
  `release/evidence/logic_analyzer_board_85m/ui_source_check/pyui_board_check.log`
  —— pyUI 的 `_run_logic_analyzer()` 四种"模式×源"组合：core+Core / uart+Core / uart+J8 / core+J8
  报文长度 **16/16/13/13**、命令码 **0xA8/0xA8/0xA5/0xA5**、`[14]` = **1/1**，**四枪全 PASS**；
  同目录 `singlefile_selftest.log` —— 单文件界面 `--selftest COM11` **六模式全部通过**
  （Core 源读数：提交 1187 拍、取指在场 1198 拍、停顿 785 拍、冲刷 4 次、窗口 IPC 0.597）。

#### 4.3 本轮发现并记录的已知限制：触发永不出现会停住固件

固件 Arm 之后**无超时**轮询采集完成位（`software/logic_analyzer/logic_analyzer.c` 第 189 行）。
若上位机发了一条永不命中的触发（例如 J8 源下等一个没接信号的外引脚上升沿），固件停在该循环：
串口不再读也不再写，**只有按板上 `REST` 或重下同一位流才能恢复**。
本轮实板复现一次（当时正在无人值守跑四种组合检查），重下 `la85` 后 `PROGRAM PASS` / done bit 1 恢复正常。

- 恢复路径与现场纪律写进 `release/materials/field_recovery_card.md` 与演示脚本 §6；
  完整说明见 `docs/application_logic_analyzer.md` §6.10.7。
- **为什么不改固件**：给 Arm 加超时需要重建位流，会作废已冻结的交付位流哈希与全部引用它的证据；
  本轮保持位流不变，按"已知限制 + 恢复路径"记录（是否改由用户决定）。
- 上位机侧已能自动识别这种情况（`bytes=0` ⇒ 直接提示恢复方法），不会再让现场去猜接线或串口。

### 5. 验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| MDU 单元 | `scripts\run_mdu_tb.ps1` | **46 项 `ALL TEST PASS`**（乘除全边界、除零、溢出、背靠背、取消） |
| M 扩展端到端 | `scripts\run_pipeline_m_ext_tb.ps1` | **`ALL M EXTENSION PIPELINE TEST PASS`**（固定延迟 + 随机背压两配置；55 条提交 trace 与单周期 Reference 逐条一致、x1~x31 + RAM 一致、每笔除法精确 34 拍） |
| CoreMark RTL 仿真 | `run_coremark_pipeline_tb.ps1`（rv32i / `-March rv32im`） | **1,251,724 / 594,792 拍**，两配置官方 CRC 全过；rv32i 与历史基线**逐位相同**（证明 M 扩展没扰动 RV32I） |
| 逻辑分析仪模块 | `scripts\run_logic_analyzer_tb.ps1` | 新增 `SRC DEFAULT / SRC SELECT / SRC CORE CAPTURE / SRC BACK TO J8` 四项 PASS |
| 上位机 | `python -m unittest discover -s python -p 'test_logic_analyzer*.py'` | **50 项 OK**（pyUI：`capture_view` 组合、界面标题与"控件真的布局出来"；单文件演示器：控件接线、切源改窗口、报文 0xA8/0xA5、view 口径） |
| **实板 5 模式验收** | `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000` | **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`** |
| **实板 Core 探针** | `scripts\run_core_probe_board.ps1 -Port COM11` | **`CORE PROBE BOARD ACCEPTANCE PASS`**（6 次采集） |
| **实板 界面双源四组合** | `scripts\run_ui_source_board.ps1 -Port COM11` | **`UI BOARD CHECK PASS`**（pyUI 真路径，四枪全 PASS，报文 0xA8/0xA8/0xA5/0xA5） |
| **实板 单文件界面六模式** | 同上脚本第二段（`python 逻辑分析仪演示.py --selftest COM11`） | **`全部通过`**（六模式 PASS，含 Core 源读数） |
| **实板 CoreMark（RV32IM @85 MHz）** | `program_board.ps1 -Config cmim85` + `score_coremark_board.ps1 -Config cmim85` | **Score 193.192 / CoreMark-MHz 2.272 / 官方 CRC PASS / 20.704 s**（4000 迭代，位流 `EE8B6536…`，WNS +0.250 ns） |
| **实板 CoreMark** | `program_board.ps1 -Config cmim` + `run_coremark_board.ps1` | **Score 113.642 / CoreMark-MHz 2.272 / 官方 CRC PASS / 17.599 s** |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0`（位流哈希已同步） |
| 板级验收（加跑 Core 源） | `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 1 -IncludeCoreSource -CoreRuns 3` | `LOGIC ANALYZER CORE SOURCE PASS captures=3` + `ACCEPTANCE PASS captures=8`（不加开关仍是 `captures=100`，冻结口径不变） |
| 交付包链（改动后重跑） | `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` | `EXPORT PASS files=298` / `MANIFEST PASS files=3936` / `AUDIT PASS final_files=299 artifacts=3` |

> 上面整轮 `run_final_regression.ps1` 在本次界面/判据改动**之后**重跑并全绿
> （`ALL AUTOMATED FINAL REGRESSION PASS`，含 `Task 30 Python/VCD tools`）；随后又补了
> `python/test_logic_analyzer_singlefile.py`（单文件演示器的界面级用例），单独重跑
> `scripts\run_logic_analyzer_python.ps1` → `ALL LOGIC ANALYZER PYTHON TEST PASS`（**50 项 OK**）。
> 导出包内 `tools/logic_analyzer_serial.py`、`tools/mes50hp_validation_ui.py`、`逻辑分析仪演示.py`
> 与仓库源文件的 SHA-256 逐一对齐（含 `capture_view`）。

### 6. 位流（本批）

| 用途 | 工程 | SHA-256 |
|---|---|---|
| 交付（85 MHz 逻辑分析仪） | `fpga/logic_analyzer_85m` | `C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F`，`All Constraints Met` |
| 备用（50 MHz） | `fpga/logic_analyzer` | `8102634A23ACB68BF9EDA4110E48A3ECFE28186A4E76D0C5717856903986B012`，`All Constraints Met` |
| RV32IM 计分 | `fpga/coremark_im` | `BE7A4FF31F2214AC12D230B4B48079B80C4A17A33C72F106ABAB407FD57D6F36`，`All Constraints Met`（WNS +1.841 ns） |
| **RV32IM 计分（85 MHz，与交付同频）** | `fpga/coremark_im_85m`（新增） | `EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1`，`All Constraints Met`（WNS **+0.250 ns**，估算 Fmax **86.8456 MHz**，4198 LUT / 3361 FF） |

> ⚠️ `fpga/coremark`、`fpga/coremark_80m`、`fpga/coremark_85m`、`fpga/coremark_90m`、
> `fpga/logic_analyzer_80m`、`fpga/logic_analyzer_90m` 的**位流文件未重建**，其已登记哈希与
> 板级结论按各自批次继续有效；但共享 RTL（`pipeline_cpu.v` / `logic_analyzer_mmio.v`）已变，
> 这些工程的**源码与位流不再一一对应**，如需重建必须重跑对应板级证据。

### 7. 已知遗留

- 归档位流（cm50/cm80/cm85/cm90/la80/la90/ila）未用新 RTL 重建，也未重测；引用时按原批次口径。
  （2026-10-14 追加：**RV32IM 的 85 MHz 计分位流已新建并实测**，见 §4.1——它不属于"归档位流"，是新构建的。）
- RV32IM 已在 **50 MHz 与 85 MHz** 两个频点实测；**80/90 MHz 未测**（85 MHz 是交付时钟，优先补这一点）。
- **触发条件永不出现会把固件停住**（无超时轮询），只能按 `REST` 或重下位流恢复；
  已在两个上位机与恢复卡里写明识别与恢复方法，见 §4.2 与 `docs/application_logic_analyzer.md` §6.10.7。
  是否给固件加 Arm 超时（需重建位流、刷新全部哈希与证据）由用户决定，本轮未改。
- 断电一致性三轮压力仍是"用户决定不做"。
- **成品材料（`technical_report.docx/.pdf`、`defense_presentation.pptx`）仍是旧产物**：
  docx/pdf 停在 2026-09-30、pptx 停在 2026-09-16，**都不含 M 扩展与双源界面**。
  两个生成器的文本已同步改对（`scripts/generate_technical_report.py`、
  `scripts/generate_defense_deck.mjs`），但本机没有 `python-docx`、
  也没有 `@oai/artifact_tool`（`docs/reproduction.md` 第 104 行记录 PPTX 只能在原环境重生成），
  因此**未重新生成**；要不要为它装依赖由用户决定。交付包本身不含这三个文件，包内一致性不受影响。

## 仪器化第四轮：仪器面板（交互旋钮）（2026-10-10 立项，2026-10-12 收口；用户批准的范围变更）

起因：用户提出"想把逻辑分析仪改成可交互的"。只读调查后确认问题不在"功能少"，
而在**固件早就有旋钮、界面却没接出来**：时基 `sample_div`、触发方式/通道/电平、
`pre`/`post`、激励速率 `pattern_div`、激励数据 `data` 全部写死在 `mode_config()` /
`default_config()` 里，而 13 字节报文的 `[1]`～`[11]` 一直把它们写进
`LA_DIV`/`LA_TR_*`/`LA_PRE`/`LA_POST`（`software/logic_analyzer/logic_analyzer.c` 第 153～158 行）。
因此本轮**只动主机端**：不改 RTL、不改固件、不重综合，位流哈希不变。
规格与边界见 `docs/application_logic_analyzer.md` §6.9，D52 例外登记见 `docs/competition_scoring.md` §6 第 ③ 条。

### 1. 改了什么

| 层 | 文件 | 改动 |
|---|---|---|
| 上位机（共享推导） | `python/logic_analyzer_serial.py` | 新增 `KNOB_FIELDS`/`apply_knobs`/`mirror_required_samples`：旋钮 → 报文的**唯一**推导处，含越界、未知字段、镜像限制与窗口校验；`run_captures` 增 `knobs` 参数，并在**打开串口之前**校验镜像窗口 |
| 上位机（界面） | `python/mes50hp_validation_ui.py` | 新增「仪器面板」：时基、触发方式/通道/电平、`pre`/`post`、激励速率/数据、板级时钟、采满 N 次后停；即时校验（错值变红并给原因）；模式相关禁用；每轮把**报文十六进制**打进日志 |
| 上位机（测试） | `python/test_logic_analyzer_serial.py`、`python/test_logic_analyzer_ui.py`（新增） | 8 项旋钮推导/校验 + 5 项面板行为（同位规则、镜像禁用、即时校验、停止条件） |
| 零依赖采集器 | `scripts/logic_analyzer_capture.ps1` | `-Oneshot`（0xA6）改为**开串口前显式拒绝**，新增默认关闭的 `-AllowUnsupportedFirmwareSegments`；头部协议注释补 0xA7 布局 |

边界未破：`rtl/*.v`、`software/logic_analyzer/*`、`.fdc` 与位流一字未改；
单文件上位机 `逻辑分析仪演示.py` 本轮不动（旋钮只长在一个界面上，避免两份推导）。

### 2. 本轮修掉的口径与死路径

| # | 问题 | 根因 | 处理 |
|---|---|---|---|
| 1 | `-Oneshot` 现场误用会卡住 | 发 0xA6，而交付固件只认 0xA5/0xA7（`logic_analyzer.c` 第 214 行），失败形式是等满超时（默认 70 s） | 开串口前抛错；显式开关可越过（实测越过后的错误变成"串口打不开"，证明拦它的是闸门） |
| 2 | 上一轮文档口径不准 | `docs/progress.md` 原文说 `-Segmented` 也发 0xA6；**实际只有 `-Oneshot` 发**，`-Segmented` 拼的是同目录已有日志 | 在本轮记录里更正，并保留主机端拼接路径（实测 `-Segments 20` 重建 `pages=1` PASS） |
| 3 | 关窗时 Tk 报 `invalid command name "..._poll_events"` | 窗口销毁后仍有排队中的 `after` 轮询回调 | `destroy()` 里先 `after_cancel` 再销毁 |

### 3. 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 上位机全部单测 | `python -m unittest discover -s python -p 'test_logic_analyzer*.py'` | **24 项 OK**（原 9 项 + 新增 15 项） |
| 上位机入口 | `scripts\run_logic_analyzer_python.ps1` | `ALL LOGIC ANALYZER PYTHON TEST PASS`（子进程退出码 0） |
| **不勾面板时逐字节不变** | 与交付包旧版 `tools/logic_analyzer_serial.py` 对拍：5 模式 × 2 时钟 × 2 波特率 | **报文与 cfg 0 处不符** |
| 零依赖采集器离线重建 | `scripts\logic_analyzer_capture.ps1 -FromCaptures <目录> -Modes static,counter,uart,spi,mirror` | `WAVEFORM REBUILD PASS pages=5` |
| 主机端分段拼接仍可用 | 同上 + `-Segments 20` | `WAVEFORM REBUILD PASS pages=1` |
| `-Oneshot` 拒绝 | 不带开关 / 带显式开关 | 前者开串口前抛错；后者越过闸门后变成串口 IOException |
| 脚本语法与 BOM | `ensure_ps1_bom.ps1` + `Parser::ParseFile` | `PS1 BOM FIXED: logic_analyzer_capture.ps1`、`PARSE OK` |
| **完整最终回归** | `scripts\run_final_regression.ps1` | **`ALL AUTOMATED FINAL REGRESSION PASS`，`FINAL_REGRESSION_EXIT=0`，PASS=54 / FAIL=0** |
| **位流未被触碰** | 同上（回归里的 `Require-Artifact` 逐份算 SHA-256） | la85 交付=`8908FD8C…`、la50 备用=`FDDF038C…`，与上一轮**逐位一致** |

> 复现提示：本轮**第一次**跑最终回归 PASS（54/54），**第二次**在
> `Task 28 initialized FPGA memory model` 步骤失败，原因是
> `fpga/coremark/rtl/coremark_imem.mem` 被别的进程短暂占用
> （`Set-Content : ... because it is being used by another process`）。
> 当时机器上已无 PDS/iverilog/python 进程，占用者未定位，怀疑是短时的文件索引或安全软件扫描；
> **第三次重跑即恢复**（`FINAL_REGRESSION_EXIT=0`、54/54）。
> 这条记下来是因为它会让"回归失败"看起来像代码问题：判断依据应是**同一命令重跑是否复现**，
> 而不是第一次的退出码。

### 4. 板级 100/100 与交付包收口（2026-10-12，用户批准后补做）

| 步骤 | 命令 | 结果 |
|---|---|---|
| 下载交付位流 | `scripts\program_board.ps1 -Config la85` | `PROGRAM PASS config=la85`、`done bit is 1`；SHA256 `8908FD8CB3AE72ED…` |
| 板级探测（1 次/模式） | `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 1 -ClockHz 85000000 -Output results\probe` | `LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=5`（J8 跳线在位；样本数 static 5 / counter 5 / uart 207 / spi 85 / mirror 2048） |
| **板级正式验收（20 次/模式）** | `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000 -Output results\board_final_20261012` | **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`**，作业退出码 0 |
| 证据页重建 | `logic_analyzer_capture.ps1 -FromCaptures results\board_final_20261012 -Modes static,counter,uart,spi,mirror` | `WAVEFORM REBUILD PASS pages=5` |
| 证据归档 | 先备份旧目录，再替换 `release/evidence/logic_analyzer_board_85m/` | 306 文件（5 模式 × 61 + 总览页），与旧目录**同形**；旧证据备份在 `results/evidence_backup_85m_20261012/`（306 文件） |
| 演示前自检 | `demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0` |
| 发布链（pwsh 7.6.5） | `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` | `FINAL SUBMISSION EXPORT PASS files=296` / `RELEASE MANIFEST PASS files=3891` / `RELEASE PACKAGE AUDIT PASS final_files=297 artifacts=3`（三个退出码均 0） |
| 包内核查 | 仓库源文件与包内副本逐份 SHA-256 比对 | `tools/mes50hp_validation_ui.py`、`tools/logic_analyzer_serial.py` 与仓库源文件**逐字节一致**；包内板级证据 = 本批（`mirror/summary.json` 哈希相同、306 文件） |
| 最终回归（改动后复跑） | `scripts\run_final_regression.ps1` | **`FINAL_REGRESSION_EXIT=0`、PASS=54 / FAIL=0**（改过 `scripts/` 与证据后按 handoff §4 复跑） |
| **实板旋钮路径验证** | 直接调 `run_captures(..., knobs=...)` 打真板：① UART 改速率 `pattern_div 433→866` 且 `sample_div 26→52`（重算后位点数仍是 16）② 镜像改窗口 `post 2047→1200` | 两次都 PASS：UART 208 点 / 触发 16，且 UART 字节解对；镜像 1201 点，且**逐字节解出 `HELLO,RISC-V`**。证明"旋钮 → 报文 → 实板采集 → 判据"整条链在真板上成立（证据 `results/knob_probe/`） |

**发布链上撞到并修掉的一个既有缺陷**：
`scripts\export_final_submission.ps1` 第 276 行的 README 模板写了单反引号的 Markdown 代码段
（`` `uart0_rx` ``）。PowerShell 7 把 `` `u `` 当作 Unicode 转义 `` `u{...} `` 的起始，
于是**整个脚本在 pwsh 7 下解析失败**
（`ParserError: The Unicode escape sequence is not valid ... @line 276`），导出以 `EXPORT_EXIT=1` 中断。
旁证：交付包 README 第 53 行原本显示成"镜像 uart0_rx"，反引号被吃掉——
说明**上一次成功导出实际上是用 PowerShell 5.1 跑的**（5.1 里 `` `u `` 只是普通字符），
与 `docs/demo_runbook.md` "发布脚本必须用 pwsh 7"的要求不符。
处理：按同一文件第 255 行已有的写法把该行改成成对反引号（`` ``uart0_rx`` ``），
再用 `ensure_ps1_bom.ps1` 补回编辑工具去掉的 BOM。修复后 pwsh 7 下 `scripts\*.ps1` 解析全绿
（修复前只有它一个失败），README 第 53 行的反引号也恢复正常。

**仍未处理的同类外观问题（本轮未动，等用户决定）**：同一 README 模板还有约 20 处单反引号代码段
（例如 `` `scripts\run_final_regression.ps1` ``）。它们在 PowerShell 字符串里同样会丢掉反引号，
生成的 README 第 59 行因此显示为"scripts\run_final_regression.ps1"。
这一类**不会**导致解析失败（只有 `` `u `` 会），只是 Markdown 标记丢失，修法相同。

**其余未做**：

1. **新测试已自动进最终回归**：`python/test_logic_analyzer_ui.py` 与
   `python/test_logic_analyzer_serial.py` 的 15 项新用例都落在
   `run_logic_analyzer_python.ps1` 的发现范围 `test_logic_analyzer*.py` 内，
   而该入口由 `run_final_regression.ps1` 第 70 行调用，无需另加入口。
2. **发现一个既有的红测试（不是本轮引入）**：`scripts\run_waveform_viewer_test.ps1` 的
   `waveform-page-mirror_00` 判据要求状态栏出现字面量 `' ns'`
   （`scripts/waveform_viewer_test.js` 第 318 行），而镜像页的时基是 1082 ns/点，
   格式化后正确显示为 `µs`/`ms`，于是被判 FAIL。
   **证据**：改用交付包自带的模板与板级证据（都不是本轮改过的文件）跑同一条命令，同样 `FAIL count=1`，
   说明与本轮改动无关。页面本身把 Δ 报成了 `925 点 = 1.001 ms`，读数是对的，是判据写得太死。
3. **"换被测对象"仍未做**：把采集通道改接 Core 外部的总线观测点（见上一轮遗留第 2 条），
   这仍是把应用与 CPU/CoreMark 主线焊接起来的方向，属下一轮范围变更。

### 5. 单文件上位机补齐（2026-10-12，用户要求"合成一个能直接用的 py"）

用户反馈上位机散在 `tools\` 里一堆模块、不好用，要一个能直接双击的 py。
处理：把「仪器面板」搬进自包含的 `逻辑分析仪演示.py`（仓库根目录，也是交付包根目录那一份）。
它本来就自带协议、解码、测试与 VCD/HTML 导出，**不 import 仓库任何模块**。

| 项 | 改动 |
|---|---|
| 旋钮 | 移植 `apply_knobs` / `mirror_required_samples` / `_knob_int` 与全部面板控件（时基、触发方式/通道/电平、`pre`/`post`、激励速率/数据、板级时钟、采满 N 次后停） |
| **修掉一个真 bug** | "连续采集"按钮原来是**死的**：`live` 从来没被置真，点它只采一次。现在真的连续采，再点一次停止，并支持"采满 N 次自动停" |
| **对拍抓到的移植 bug** | 本文件 cfg 用 `trig_type/trig_mask/trig_value` 键名，旋钮名却是 `trigger_*`；不翻译就会被静默加成新键——**报文照发但参数没生效**。已加 `_KNOB_TO_CFG` 映射 |
| 自检钩子 | `run_gui(probe=…)` 把面板句柄交给自动化脚本，用于无人值守驱动界面（正常双击不走这条路） |

**验证（全部实测）**：

| 验证 | 结果 |
|---|---|
| 与正式模块逐字段对拍 | 5 模式 × 2 时钟 × 11 组旋钮 = **110 组、0 处不一致**（含全部拒绝分支）；`build_packet` 输出逐字节相同 |
| 真实 Tk 窗口驱动 | 默认旋钮全禁用 → 勾选后启用并预填模式默认 → 非法值变红给原因 → 切 mirror 后 `pre`/`post` 变镜像默认 |
| 连续采集 + 自动停（实板 COM11） | 计数包装器数**真实采集次数 = 3 / 期望 3**，且旋钮确实传进了 `capture()` |
| 五模式自检（实板） | `python 逻辑分析仪演示.py --selftest COM11` → **全部通过**（含 mirror 逐字符解出 `HELLO,RISC-V`） |
| 交付包同步 | export → manifest → audit 重跑通过，包内 `逻辑分析仪演示.py` 与仓库源文件一致 |

> 分工：**单文件版 = 现场用**（一个文件、双击就跑，含面板）；
> `tools\` 那一套 = 回归与批量验收用（`run_logic_analyzer_board.ps1` 调 `logic_analyzer_serial.py` 跑 100/100）。
> 两份的旋钮推导已用上面的 110 组对拍锁住一致性。


## 仪器化第三轮：八键八灯面板**整套移除**（2026-10-10，用户决定）

用户原话："按键的功能是啥啊，能不能把按键的功能去掉，我觉得没用"——按用户选择执行 **B 方案**：
按键与面板控制逻辑全部删除，**LED 退回原来的 `gpio_out[7:0]`**，读数（§6.8.3）保留不动。

| 层 | 文件 | 改动 |
|---|---|---|
| RTL | `rtl/la_panel.v` | **删除**（连同 8 键消抖、档位循环、LED 状态编码） |
| RTL | `rtl/logic_analyzer_mmio.v` | 删掉面板端口与 `panel_active` 判定；`DEPTH=2048` 与镜像采集保持原样 |
| RTL | la50/la85 板级顶层 + la85 PLL 顶层 | 删 `key_n` 接线与面板例化；`assign led = gpio_out[7:0];` 恢复 |
| RTL | la80/la90 归档顶层 | 恢复到归档位流对应的原始写法（单行例化），位流与哈希**未变** |
| 约束 | 两个活跃 `.fdc` | 删掉 KEY1..KEY8 管脚块，回到 114 行；纯 ASCII |
| 测试 | `tb/tb_la_panel.v`、`scripts/run_la_panel_tb.ps1` | **删除** |
| 测试 | `tb/tb_logic_analyzer_board_top.v` | 重写干净版：`led!==8'h5A` 断言 + 镜像检查，无按键用例 |
| 测试 | MSIM TB / 镜像 TB / 80M 归档 TB | 去掉 `key_n` 接线与面板断言，回到各自基线行为 |
| 脚本 | `export_final_submission.ps1`、`run_final_regression.ps1`、两个板级 TB 入口 | 删掉面板相关条目 |

**关键证据——移除是干净的**：重建后位流的资源/时序
（LUT 4479 / FF 3610（实现 3601）/ DRM 6.0 / WNS +0.588 / WHS +0.310 / Fmax 89.4721 MHz）
与**加面板之前**逐项一致；板级复测 `captures=100 PASS`；`demo_preflight.ps1` PASS warnings=0。
新哈希：**la85 = `8908FD8C…`**、**la50 = `FDDF038C…`**（已同步进 `demo_preflight.ps1` 与 `claims_map.md`）。

**踩到的坑**：PDS 会拒绝 `DEPTH=2048` 下复位期的 BRAM 清零循环（`Loop limit 2000`），该循环已删除；
`.sbit` 内含构建时间戳，**同样 RTL 重建哈希也会变**，所以哈希只能靠"重建后同步"而不能靠比对。

### 交付包同步（2026-10-10 第三轮同日收口）

| 步骤 | 命令 | 结果 |
|---|---|---|
| 重新导出 | `scripts\export_final_submission.ps1` | `FINAL SUBMISSION EXPORT PASS files=296` |
| 重建清单 | `scripts\create_release_manifest.ps1` | `RELEASE MANIFEST PASS files=3881` |
| 交付审计 | `scripts\audit_release_package.ps1` | **`RELEASE PACKAGE AUDIT PASS final_files=297 artifacts=3`** |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0` |

- 包里已无任何面板残留（无 `la_panel.v` / `tb_la_panel.v` / `key_n`，MMIO 端口 0 处 `panel` 引用），
  两个位流哈希与 `claims_map.md` 逐位一致。
- **新增进包**：单文件上位机 `逻辑分析仪演示.py`（包根目录）。按用户选择"文件进包、
  `启动逻辑分析仪.cmd` 仍指向 `tools\pyUI.py`"，两条上位机路径并存；审计的必需文件表已加这一条。
- README 同步：五模式（含 mirror）波形预览说明、镜像采集命令行，并把"四模式 80/80、深度 256"
  明确标注为 **2026-09-29 历史记录**；当前交付位流一栏写 **2026-10-10 五模式 100/100、深度 2048**。
- **修复一个导出中断**：PDS GUI 打开交付包时会在包内自建并清理 `temp_projects\`，文件在
  "枚举完 → 开始哈希"之间消失，导出在最后一步 `Get-FileHash` 抛 PathNotFound 中断（包内容已写好、
  只缺 `SHA256SUMS.txt` 与 zip）。现导出与审计**统一把 `temp_projects/` 与 `sim/` 一起按构建垃圾排除**。
- **提交包（新增脚本）**：`scripts\build_submission_bundle.ps1` 把"交付包 + 完整工程源码"打成一个
  压缩包放桌面（`RISC-V_CPU_2026_提交包_20261010.zip`，2412 个文件 / 解压 70.9 MB / 压缩 7.5 MB）：
  `01_交付包/`（= 已过审计的那一份，296 个文件按包内 SHA256SUMS.txt 逐条复核，0 处不符）
  + `02_工程源码/`（rtl/tb/software/python/scripts/docs/third_party + fpga 各工程源码、约束、
  工程文件、位流、时序报告）+ `先读我.txt`。
  排除：`release/materials`（旧版报告/PPT，用户决定不进包）、`tmp/`、`.git/`、`node_modules/`
  （7796 个文件 / 320 MB，第一版误收导致包涨到 109 MB）、FPGA 综合与布局布线中间产物。

## 仪器化：读数 + 面板（2026-10-10 第二轮，用户批准的范围变更）
> ⚠️ 本轮的**面板部分已在同日第三轮被用户否决并整套移除**（见上），下面保留作历史记录；
> **读数部分仍然有效**。涉及 `la_panel.v` / 面板 TB / 按键现场步骤的表述均已作废。

起因是用户看完波形页的一句反馈："逻辑分析仪有点太单薄"。诊断出的三条根因：

1. **被测对象是它自己**（激励→回环→抓自己）——真仪器测的是别人的信号；
2. **只给曲线不给读数**——仪器的价值在结论（频率、周期、占空比、帧错误），原来一个数都没有；
3. **没有面板**——板上的 8 键 8 LED 闲置，拔掉 USB 这台"仪器"什么都不说。

本轮做第 2、3 条（第 1 条"换被测对象"是更大的方向，见文末遗留）。

### 1. 仪器读数（纯上位机，零位流风险）

`逻辑分析仪演示.py` 里新增测量层，界面右侧多一张读数表：

- **每通道**：上升沿/下降沿数、频率、周期（中位数）、周期抖动 min…max、占空比、最小/最大脉宽；
  不足两个边沿标 `—`（直线测不出频率，硬报 0 Hz 是假读数）。
- **协议层**：帧数/字节数、帧错误、每位采样点、位宽、推算波特率、解码内容。
- 与判据**同源**：界面、网页波形页、Markdown 报告、`--selftest` 共用同一套函数；
  新增"导出测量报告"（Markdown，含测量条件与读数口径）。
- 已按实板校准：mirror 位宽 8658.8 ns vs 真实 8680 ns（**−0.24%**，是"每比特 8 个采样点"的
  量化误差，口径照实写进文档）；SPI 的 SCLK 10.62 MHz（周期取中位数后偏差 0.00%）。
  踩到两个真坑并已修：纳秒值被通用 SI 格式化印成 `8.659 ks`；周期用平均值被字节间隙带偏。

### 2. 仪器面板（要动 RTL + 约束 + 位流）

| 层 | 文件 | 改动 |
|---|---|---|
| RTL 新模块 | `rtl/la_panel.v` | 8 键两级同步 + 1.2 ms 消抖 → 单拍控制脉冲；时基档位按 `CLK_HZ` 参数算；LED 状态编码 |
| RTL | `rtl/logic_analyzer_mmio.v` | 增加面板输入/状态输出端口；面板未激活时**行为与加面板前逐位相同**（用 `=== 1'b1` 判定，z 即为假） |
| RTL | la50/la85 板级顶层 + PLL 顶层 | 接 `key_n[7:0]`，例化面板，LED 改由面板驱动 |
| RTL | la80/la90 归档顶层 | 只加显式常量接线（PDS 原本就把未驱动输入 tie 0，功能等价），位流与哈希**未变** |
| 约束 | 两个活跃 `.fdc` | 增加 KEY1..KEY8 管脚（K18,L15,J17,K16,J16,J19,H20,H17，LVCMOS33） |
| 测试 | `tb/tb_la_panel.v` + `scripts/run_la_panel_tb.ps1`（新增） | 消抖、单拍脉冲、档位循环、LED 状态、KEY7 交还；已进最终回归 |
| 测试 | 板级 TB + MSIM TB | LED 断言从 `led==0x5A`（那是 gpio_out）改成面板状态；新增**按键直接 Arm/Clear** 的端到端用例 |

面板定义（按键/LED 含义）与现场人工步骤见 `docs/application_logic_analyzer.md` §6.8。

### 3. 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 面板单测 | `scripts\run_la_panel_tb.ps1` | `ALL LOGIC ANALYZER PANEL TEST PASS` |
| 板级按键（仿真） | `scripts\run_logic_analyzer_board_top_tb.ps1` | `PANEL LED / CLEAR / ARM PASS`（按键独立完成一次采集） |
| 读数（实板） | `逻辑分析仪演示.py --selftest` | 五模式读数与已知参数吻合（含 −0.24% 量化口径） |
| **面板不破坏原通路** | `run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` | **`captures=100` PASS** |
| 最终回归 | `scripts\run_final_regression.ps1` | **`ALL AUTOMATED FINAL REGRESSION PASS`**（含面板 TB） |
| 交付包 | export → manifest → audit | `EXPORT PASS files=297` / `MANIFEST PASS files=3881` / **`AUDIT PASS final_files=298`** |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0` |

位流：**la85 交付 = `005BD00B8C001FFE…`**、**la50 备用 = `ED38436EBE15CDE4…`**（两处哈希已同步进
`demo_preflight.ps1` 与 `claims_map.md`）。资源/时序：LUT 4775、FF 3792（实现 3776）、DRM 6.0、
Setup WNS +0.527 ns、Hold WHS +0.226 ns、估算 Fmax 88.9864 MHz，`All Constraints Met`。

### 4. 本轮踩到的坑（详见 `docs/debug_log.md`）

PDS `Verilog-4086` 双驱动（iverilog 容忍、综合器拒绝）；`.fdc` 只收 ASCII 且注释符是 `#` 不是 `//`；
板级 TB 的并行 initial 被 `$finish` 截断导致"假通过"；读数单位与中位数两个显示缺陷；
交付导出被**用户开着的 PDS 图形界面**锁住而中断一次（重跑即恢复，交付包已重新导出通过审计）。

### 5. 仍未做（需要用户决定）

1. **实体按键只能人工验**：`docs/application_logic_analyzer.md` §6.8.5 给了 6 步现场流程
   （按 KEY1 看 LED2/LED3 亮、按 KEY3 清、KEY4-6 换档、KEY7 交还）——脚本看不见 LED，必须人眼确认并录像。
2. **"换被测对象"没做**：把采集通道改接 Core 外部的总线观测点，做成"CPU 总线行为分析仪"。
   这是把应用与 CPU/CoreMark 主线焊接起来的最大加分方向，但要动 SoC 观测层，属于下一轮范围变更。
3. `release/materials/` 成品材料（技术报告 docx/pdf、答辩 QA、视频稿）仍含旧数字，上一轮已记录在案。


## 镜像抓取：上位机发字符串、逻辑分析仪抓这根线（2026-10-10）

起因：板级演示"展示效果差"——UART/SPI 页抓的是 pattern_gen **重复发送的同一个字节**
（UART=`0xA5` 且不可打印、SPI=`0x3C`），窗口只有 240/85 点，static/counter 页更是只有 **5 个点**；
页面本身的渲染能力（缩放、光标、帧标注、VCD）一直够用，差的是**被抓的内容**。

本轮把被测信号换成"上位机真正发出去的串口线"：上位机发一句 ASCII（默认 `HELLO,RISC-V`），
逻辑分析仪抓下来并把整句报文**逐字符标在波形上**。规格与验收口径见
`docs/application_logic_analyzer.md` §6.7。

### 1. 改了什么

| 层 | 文件 | 改动 |
|---|---|---|
| RTL | `fpga/logic_analyzer{,_80m,_85m,_90m}/rtl/mes50hp_logic_analyzer_top.v`（各 1 行） | `assign loopback_tx={uart0_rx,sample_outputs[6:0]}`：ch7（J8-31/32）改为镜像上位机串口线 |
| RTL | `rtl/logic_analyzer_mmio.v` | 新增 `parameter DEPTH=2048` 并传给 `capture_engine`；`rtl/capture_engine.v` 仅删掉复位清 BRAM 的 for 循环（DEPTH=2048 时超过 PDS `Loop limit 2000`） |
| 固件 | `software/logic_analyzer/logic_analyzer.c` | 新命令 `0xA7`（镜像，13 字节布局不变、`[10]\|[11]` 改 16 位 post）；Arm 后打印 `LA_ARMED`；解码改流式（不再用栈上 1 KB 的 `raw[256]`） |
| 上位机 | `python/logic_analyzer_serial.py`、`scripts/logic_analyzer_capture.ps1` | `mirror` 模式 + `--text/-MirrorText`；采样分频按**板级时钟与波特率**算（85 MHz→91、50 MHz→53）；判据 = 解出的字节**逐字节等于**发出去的字符串 |
| 波形页 | `python/waveform_viewer.html` | 帧标注加字符（`'H' 0x48`）、状态栏直接打印 `报文 "HELLO,RISC-V"` |
| 测试 | `tb/tb_logic_analyzer_mirror.v` + `scripts/run_logic_analyzer_mirror_tb.ps1`（新增，已入最终回归） | 真实板级顶层 + 真实固件；J8 八对回环用 `assign` 模拟；场景 A 短报文冒烟、场景 B 整句 + 2048 点（与交付配置一致） |

边界未破：Core 源码、端口与事务语义一个字未改；不新增寄存器；8 路物理回环保留（ch7 的激励源换成上位机串口线）。

### 2. 顺带修掉的四个真 bug（全部由证据定位，不是猜的）

| # | 现象 | 根因 | 证据 |
|---|---|---|---|
| 1 | 固件把线上真实的 `0xA5` 解成 `0x4A` | `decode_uart` 在位边界取样，缺 2026-09-30 给 Python/PowerShell 补的半比特居中 | `release/evidence/logic_analyzer_board_85m/uart/uart_00.log` 的 `UART:0000004A` |
| 2 | 上位机把实板捕获解成乱码，而板上固件解对了 | Python/PowerShell/JS 三处解码器都从 `i=1` 起扫；镜像 `pre=0` 时第 0 个采样点**就是**起始位 | 实板 `mirror_00.log`：固件 `ascii=HELLO,RISC-V`，上位机 `b'\x1511=,RISC-V'` |
| 3 | 12 个字符错 5 个（`HE??RI??-V`） | 解码器成功后固定跳 10 个比特；实板采样边沿有 ±1 点抖动、帧长在 79~81 点浮动，误差逐帧累积到半个比特 | 实板 run-length：`(72,1,9)`、`(137,1,7)`；改成"每帧用自己的起始位重新对齐"后 4 次全对 |
| 4 | SPI 从 20/20 PASS 变 FAIL | 触发在 SCLK 上升沿，而 pattern_gen 自由运行 → 窗口落在字节**任意 bit** 上；落 b6 就只剩 7 个脉冲、CS 提前拉高、整字节被（正确地）丢弃。老固件的 PASS 一直是**相位运气** | `spi_00.log` 位图：7 个脉冲后 CS 拉高；改触发 CS 下降沿后稳定 |

第 3 条的修法在 Python、PowerShell、波形页 JS 与固件流式解码器**四处同改**——
"判据与标注必须同源"这条纪律在本次是硬约束：任何一处漏改，页面上标的字节和判据用的字节就不是同一个。

### 3. 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 镜像端到端（仿真） | `scripts\run_logic_analyzer_mirror_tb.ps1` | `ALL LOGIC ANALYZER MIRROR TEST PASS`（场景 A + 整句 2048 点，5 项检查全中） |
| 采集器/MMIO/故障诊断 | `run_capture_engine_tb` / `run_capture_engine_stress_tb` / `run_logic_analyzer_tb` / `run_logic_analyzer_fault_diag` | 全部 PASS（含 `reset clears`、四场景故障定位） |
| 板级顶层（50/80 MHz） | `run_logic_analyzer_board_top_tb` / `run_logic_analyzer_pll80_board_top_tb` | PASS，含新增的"ch7 每拍镜像 uart_rx"断言 |
| 波形页/解析器 | `run_waveform_viewer_test.ps1`、`python -m unittest discover -s python/tests` | `ALL TEST PASS`、16 项 OK（含相位偏移用例） |
| **实体板五模式验收** | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20 -ClockHz 85000000` | **`LOGIC ANALYZER PHYSICAL BOARD ACCEPTANCE PASS captures=100`**（四模式各 20 + 镜像 20） |
| 备用位流冒烟 | 同上 `-Config la50 -ClockHz 50000000 -RunsPerMode 3` | `captures=15`（5 模式 ×3）；证据 `release/evidence/logic_analyzer_board_50m_recheck/` |
| 板级波形页 | `logic_analyzer_capture.ps1 -FromCaptures … -Modes static,counter,uart,spi,mirror` | `WAVEFORM REBUILD PASS pages=5`；镜像页 2048 点、ch7/PC_TX、每比特 8 点、`框出=0x48` |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0`（6 个位流哈希全部对齐，含重打后的 la85/la50） |
| **最终回归** | `scripts\run_final_regression.ps1` | **`ALL AUTOMATED FINAL REGRESSION PASS`**（含新增的镜像 TB；CoreMark/GCC 等价/流水线/Hazard 全绿） |
| 交付包导出 | `scripts\export_final_submission.ps1` | `FINAL SUBMISSION EXPORT PASS files=295`（10-09 为 178，新增镜像证据与页面） |
| 交付清单 | `scripts\create_release_manifest.ps1` | `RELEASE MANIFEST PASS files=3874` |
| 交付包审计 | `scripts\audit_release_package.ps1` | `RELEASE PACKAGE AUDIT PASS final_files=296 artifacts=3` |

位流：**la85 交付 = `66A1E9A74A9C55CC…`**（原 `788F1CEB…`）、**la50 备用 = `0477DDA4B8D308B3…`**
（原 `BCAE040A…`，旧位流备份在 `tmp/la50_archived_BCAE040A.sbit`）。两个哈希已同步进
`scripts/demo_preflight.ps1`，否则现场自检会为错误的原因拦下演示。

### 4. 止损记录

DEPTH 从 256 提到 2048 时，PDS 编译先以 `Verilog-4092: capture_engine.v line 32 Loop limit 2000 exceeded`
失败（复位清 BRAM 的 for 循环）。按"不改已验证行为"的最小原则，只删掉那条复位清零循环
（导出口径完全由 `capture_count/start_index` 决定，窗口外旧数据软件读不到），
`capture_engine` 的独立 TB 与压力 TB 全部仍然 PASS。资源与时序未退化：
85 MHz 交付位流 `Design Summary : All Constraints Met`，LUT **4479**（原 4814）、FF **3610**（原 3858）、
DRM **6.0**（原 5.5 等效块）、Setup WNS +0.588 ns、Hold WHS +0.310 ns、估算 Fmax **89.4721 MHz**，
2048×8 存储未被推成分布式 RAM（`LUT as Distributed RAM = 0`）。LUT/FF 反而下降，
是因为去掉复位清零循环省下了逻辑。

> 本机**没有安装 PowerShell 7**（`pwsh` 不在 PATH 也不在常见安装目录），
> 本轮 `export_final_submission.ps1` / `create_release_manifest.ps1` / `audit_release_package.ps1`
> 是用 Windows PowerShell 5.1 跑通的（脚本自身注释已声明两者在"UTF-8 无 BOM"上行为一致）。
> `docs/demo_runbook.md` 里"必须用 pwsh 7"的要求在本机无法满足，需要用户在有 PS7 的机器上复核一次。

### 5. 关于 la80 / la90：**故意不重打**

目标的原始表述里包含"重打 la80/la90"，实际执行时判断**不应该重打**：
`fpga/logic_analyzer_80m` 是已记录的 80 MHz 时频点（板级四模式 80 次通过），
`fpga/logic_analyzer_90m` 是"CoreMark 通过、逻辑分析仪 SPI 挂死"的归档失败点。
一旦重打，它们已记录的 Fmax/资源与板级结论就全部失效，还要连带改 claims_map §8。
所以本轮把这两个工程**恢复成与各自归档位流一致的状态**（`assign loopback_tx=sample_outputs;`、
程序镜像 `E3C3CD4A6997CD2A…`），只加了一条说明注释；
`tb_logic_analyzer_pll80_board_top.v` 的断言也改回归档口径（不含镜像），
镜像断言只留在 50m 交互工程与新增的镜像 TB 里。la80/la90 位流哈希因此未变
（`0388100A…` / `0315374E…`）。

### 6. 本轮明确没做（需要用户决定）

1. **`release/materials/` 的成品材料没有重新生成**。`scripts/generate_technical_report.py`
   里的数字与哈希已经改对（Raw 深度 2048、五模式 100/100、镜像抓取、新位流 SHA、
   资源 4479/3610/6.0、WNS +0.588/WHS +0.310/Fmax 89.4721），但 `technical_report.docx/.pdf`
   仍是旧产物；本机**没有装 python-docx**，生成脚本跑不起来，PDF 转换工具链也未确认。
   同理 `release/materials/defense_qa.md`、`video_script.md`、`live_demo_script.md`
   尚未加入镜像演示段落（用户此前已要求 PPT 不重新生成）。
2. **soak 复测仍是旧位流的**：`logic_analyzer_board_85m_soak/` 是 `788F1CEB…` 那一版的
   3 轮 × 80 次记录；新位流只做了 100 次（5 模式 ×20）。若要"新位流也有 soak"，需要再跑 3 轮。
3. 演示视频、答辩走位与现场话术未重录（镜像页现在是最抢眼的一张图，建议放在 S1 正中间）。



## 上位机波形链一致性修复（2026-10-09）

本轮**只动上位机工具、导出脚本与文档**，未改任何 RTL、固件、约束或位流。

### 1. 修掉了三处"看着都对、其实对不上"的不一致

| # | 不一致 | 证据 | 修复 |
|---|---|---|---|
| 1 | `python/` 里的上位机工具被冲回 9 月旧版：`logic_analyzer.py` 没有 `write_waveform_page`，`logic_analyzer_serial.py` 没有 `on_run`，UI 没有实时波形面板 | `python python/tests/test_waveform_page.py` → `ImportError: cannot import name 'write_waveform_page'` | 以 `tmp/pkg_cm_verify/tools/`（10-03 含面板的完整快照）恢复四个工具文件，并按 10-09 的测试契约把 `write_waveform_page` 的可选字段补回 |
| 2 | 交付包根目录 `波形预览.html` 是 10-03 旧模板（无 `decodeUart`/`drawByteLabels`/`zannot`），而 `release/evidence/logic_analyzer_board_85m/` 下 10-09 重新生成的页面是新版 | 逐项 grep 对照 | 用 `scripts\logic_analyzer_capture.ps1 -FromCaptures release\evidence\logic_analyzer_board_85m` 离线重建 4 个模式页 + 总览页，再重新导出交付包 |
| 3 | `scripts/demo_preflight.ps1` 的文件清单里写着 `scripts/show_capture.ps1` | 现场会 `FAIL demo files`，而 `docs/demo_runbook.md` 记的是 `warnings=0` | 清单改为 `scripts/logic_analyzer_capture.ps1`（并加入 `python/waveform_viewer.html`），`show_capture.ps1` 若存在则作为兼容项追加 |

### 2. 导出流程加固（被构建垃圾卡死 → 半成品包）

`export_final_submission.ps1` 过去对包内**所有文件**算哈希，而审计的交付物集合排除 `.lock`/`.log`/`sim/`。
PDS 打开过交付工程后 `pds.log` 被别的进程独占，`Get-FileHash` 抛 ReadError，导出在最后一步中断，
留下"内容已更新但缺 `SHA256SUMS.txt` 与 zip"的半成品。现已把哈希清单与 zip 打包都改成与审计同一套排除规则。
另外记录一条操作纪律：编辑该脚本后必须补回 UTF-8 BOM，否则 PS 5.1 按 ANSI 解码中文会报
`Unexpected token '}'` 与 `The string is missing the terminator: "@`。

### 3. 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 波形页注入单测 | `python python\tests\test_waveform_page.py` | 6 项 OK |
| 实时面板单测 | `python python\tests\test_waveform_panel.py` | 10 项 OK |
| 定时器串口解析 | `python python\tests\test_timer_demo_serial.py` | ALL PASS |
| 上位机工具单测 | `python -m unittest test_logic_analyzer test_logic_analyzer_serial test_coremark_serial` | 8 项 OK |
| 波形查看器端到端 | `scripts\run_waveform_viewer_test.ps1` | `ALL TEST PASS`（含四模式页面与总览页） |
| Python/VCD 回归入口 | `scripts\run_logic_analyzer_python.ps1` | `ALL LOGIC ANALYZER PYTHON TEST PASS`，exit 0 |
| 演示前自检 | `scripts\demo_preflight.ps1 -Port COM11` | `DEMO PREFLIGHT PASS warnings=0` |
| 交付包导出 | `scripts\export_final_submission.ps1` | `FINAL SUBMISSION EXPORT PASS files=178` |
| 交付清单 | `scripts\create_release_manifest.ps1` | `RELEASE MANIFEST PASS files=3679` |
| 交付包审计 | `scripts\audit_release_package.ps1` | `RELEASE PACKAGE AUDIT PASS final_files=179 artifacts=3` |

位流未重新综合，三处副本 SHA-256 仍为 `788F1CEB273FA626…1622DCE2`。

### 4. 已知遗留（本轮未动，需用户决定）

- `scripts\logic_analyzer_capture.ps1` 的 `-Segmented` / `-Oneshot -Segments N` 会发 **0xA6** 前缀命令，
  但 `software/logic_analyzer/logic_analyzer.c` 只认 **0xA5**（`do { packet[0]=uart_getc(); } while (packet[0]!=0xA5u);`）。
  也就是说这条路径在当前交付固件上不可能成功，失败形式是超时（默认 70 s）或按 0xA5 对齐后
  `LA_CONFIG_ERROR`。**现场误用会当场卡住**，建议要么加"当前固件不支持分段"的显式拒绝，要么整段移除。
  → **2026-10-10 第四轮已按"显式拒绝"处理**（见本轮记录 §2 第 1 条）。
  同时更正本条的**口径**：发 0xA6 的只有 `-Oneshot`；
  `-Segmented` / `-Segments N`（不加 `-Oneshot`）拼的是同目录下已有的 `<mode>_NN.log`，
  不发 0xA6，实测仍可用（`-Segments 20` 重建 `pages=1` PASS）。
  交付固件实际认的是 **0xA5 与 0xA7** 两个前缀，不是只有 0xA5。
- `scripts\run_waveform_viewer_test.ps1` 仍未接入 `run_final_regression.ps1`；
  `python/tests/` 也不在 `run_logic_analyzer_python.ps1` 的发现范围内（只发现 `test_logic_analyzer*.py`）。
- `release/evidence/logic_analyzer_board/` 是另一个位流批次（`cpi50m`）的证据页，本轮未重建。

## 交付冻结收口（2026-09-17，CPI 专项之后）

### 1. 目录与文件命名去 taskNN 化（不改行为）

开发期的 `taskNN_*` 命名全部改成功能化命名；**文档里的 “Task NN” 过程叙述保留不动**（那是 `docs/roadmap.md` 的任务编号，不是文件名）。

| 现在 | 原 |
|---|---|
| `fpga/coremark`、`fpga/coremark_80m` | `fpga/task28_coremark`、`fpga/task28_coremark_80m` |
| `fpga/coremark_ila` | `fpga/task29_coremark_ila` |
| `fpga/logic_analyzer`、`fpga/logic_analyzer_80m` | `fpga/task30_logic_analyzer`、`fpga/task30_logic_analyzer_80m` |
| `fpga/pipeline_soc`、`fpga/soc_demo` | `fpga/task26_pipeline_soc`、`fpga/task16_soc` |
| `software/logic_analyzer`、`c_smoke`、`c_array_control`、`mmio_demo`、`gpio_only`、`uart_only`、`hello_uart` | `software/task30_*`、`task14_*`、`task16_mmio_demo`、`task17_*`、`task3_hello` |
| 脚本 / TB / 测试程序 共 24 + 18 + 18 个文件 | `run_taskNN_*.ps1`、`tb_taskNN_*.v`、`tb/data/taskNN_*.mem` 等 |

连带修正（都是改名暴露出来的既有脆弱点，不是新功能）：
- `run_soc_harness_tb.ps1` 原来依赖仓库里**已存在的旧固件产物**、自己不做 `make`；固件改名后立刻暴露。已改为自己构建 `software/mmio_demo`。
- 发布审计 `audit_release_package.ps1` 原来把位流哈希**写死**成上一版，任何一次重新综合后必然失败；已改为以 `fpga/logic_analyzer/generate_bitstream/…sbit` 为唯一真实来源，要求三处副本一致。
- 同一审计用 `rg` 做命名检查，本机无 ripgrep 时会中断审计；已加 PowerShell 回退实现（保留「交付包不得出现 taskNN」这条检查）。
- 导出脚本原来整目录删除发布目录，被 PDS GUI 的 `.pds.lock` 占住时会删到一半失败；已改为逐项删除并跳过被占用条目。

验证：`run_final_regression.ps1`（-Quick 与全量）均 `ALL AUTOMATED FINAL REGRESSION PASS`；
6 个 PDS 配方的 `add_design` 相对路径逐个校验存在（0 缺失）；未重建位流，以免动到已上板验证的哈希。

### 2. 实体板 ILA 波形（赛题明确要求的一项）

用 PDS Fabric Debugger 的 TCL 模式（`cdt_dbg.exe`，**不需要点 GUI**）在板子上抓到了 CoreMark 运行中的真实流水线波形：
512 拍窗口、**IPC 0.635 / CPI 1.575**（与整段板级 CPI 1.5388 相差 2.3%），
窗口内 **84.3% 的提交指令落在 libgcc 的软件乘法 `__mulsi3`**，其中数据相关的 `beq` 是 44 次 flush 的主要来源。

证据与复现步骤：`release/evidence/ila_coremark/README.md`；分析脚本 `python/ila_coremark_analysis.py`；
诊断位流构建入口 `scripts/run_coremark_ila_pds.ps1`。

### 3. 发布包已用当前位流重新导出

`export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 全部 PASS：
`FINAL SUBMISSION EXPORT PASS files=206`、`RELEASE MANIFEST PASS files=1963`、`RELEASE PACKAGE AUDIT PASS final_files=126 artifacts=3`。
包内 README 的时序/资源/位流哈希改为**导出时自动取值**（不再硬编码），当前三处位流副本一致：
`17FD57D8F12FF4DCC8FC3A66D644561973E9D75AB9286F09D2F506F94BCDB092`（LA 50 MHz，已实体板 80/80 回环验证）。
`release/artifacts/` 与包内 `evidence/logic_analyzer_board_final/` 已同步为当前位流的实测证据。

> 遗留：发布目录里仍有一个 `MES50HP_RISCV_Logic_Analyzer.pds.lock`（PDS GUI 自 14:32 起打开着该工程，占用无法删除）。
> 它被清单与审计按设计排除，不影响交付；关掉 PDS GUI 后再执行一次导出即可消除。

---

## CPI 优化专项轮（2026-09-17，T1～T3）—— Score 29.559 → 45.051

本轮只有一个目标：**降 CPI 以提高 Score**。战略前提（上一轮已用实体板证明）：
`Score = Iterations/(Total_Time × Frequency)` 等价于 CoreMark/MHz，是频率归一化的，
提频率只服务第 (2) 项「时钟频率」，**要提 Score 必须降 CPI**。

### T1：先定位，再动手（只读观测，不改 RTL）

新建与实体板**逐拍同源**的观测台（`tb/cpi_board_memory_model.v` + `tb/tb_cpi_attribution.v`
+ `scripts/run_cpi_attribution_tb.ps1`），口径自证：观测台窗口 CPI **2.342** vs 实体板 **2.3443**（差 0.1%）。

第一个错误信号：**`i_req_valid` 有 920,207/1,788,110 拍（51.5%）为低**；
相邻 IF/ID 写入间隔直方图里 **间隔 2 占 86.7%、间隔 1 只有 1 次** —— 取指只能每两拍一条。

根因在 `rtl/pipeline_cpu.v`：请求被接受的当拍 `if_req<=0`，下一拍**没有任何请求对外可见**，
要等到“响应被接收”那一拍的结尾才重新登记，因此“旧响应接收 + 新请求接受”的交接永远无法发生；
实体板取指存储器 `assign req_ready=!rsp_valid` 在交接当拍同样是 0，两边一起把取指钉在 2 拍/条。

严格对账（板级口径，每 1000 条指令）：
`2344.3 = 理想 1000 + stall 106.4 + flush 103.3 + 剩余 1134.6`，
其中剩余的主体就是“每笔取指多花 1 拍”：`2 × 766,004 = 1,532,008 拍`为取指底座，
超出理想执行的 **768,832 拍（43.0%）纯属取指串行化损失**。
`mem_block` 只占 78,158 拍（4.4%），且大多落在取指空洞里几乎免费。

**结论**：原候选「store 提前退休」「REQ→RSP 压一拍」「访存地址提前产生」都不是主要矛盾，**T2 改取指**。

### T2：一轮一块 —— 取指满速交接（`if_arm`）

| 子块 | 内容 | 单独收益（观测台 CPI） |
|---|---|---:|
| A. SoC 侧 | 取指存储器 `req_ready` 由 `!rsp_valid` 改为 `!rsp_valid||rsp_ready` | 2.342 → 2.321（−0.9%，单独无用） |
| B. Core 侧 | `rtl/pipeline_cpu.v` 接受请求当拍立即武装下一笔请求（新增 `if_arm`） | 2.321 → **1.550（−33%）** |

A 单独做几乎没有收益，证明瓶颈在 Core；两者必须一起改。逐条说明见 `docs/rtl_changes.md` 改动 2，
定位过程见 `docs/debug_log.md`，完整归因见 `docs/coremark_cpi_analysis.md`。

### 实体板 Before / After（**全部为实体板实测**）

| 指标 | Before 50 MHz | **After 50 MHz** | 变化 | After 80 MHz PLL |
|---|---:|---:|---:|---:|
| **Score** | 29.559 | **45.051** | **+52.4%** | **72.081** |
| **CoreMark/MHz x1000** | 591 | **901** | **+52.5%** | **901** |
| **CPI** | 2.3443 | **1.5388** | **−34.4%** | 1.5387 |
| ticks | 1,691,496,677 | 1,109,848,679 | −34.4% | 2,774,618,621（2500 iter） |
| cycle_count | 1,693,816,436 | 1,112,164,751 | −34.4% | 2,778,317,919 |
| instret_count | 722,513,265 | 722,746,356 | +0.03% | 1,805,613,110 |
| cycles / iteration | 1,693,816 | 1,112,165 | −34.4% | 1,111,327 |
| 运行秒数 | 33.829 | 22.196 | −34.4% | 34.682 |
| stall / cycles | 4.54% | 8.18% | 占比升高（分母变小） | 8.16% |
| load-use / stall | 9.30% | 23.27% | 真实冒险现被检出 | 23.18% |
| flush / cycles | 4.41% | 6.71% | 绝对值不变 | 6.71% |
| branch / instret | 0.275 | 0.2747 | 不变 | 0.2747 |
| 官方 CRC | 全过 `0xd340` | 全过 `0xd340` | 一致 | 全过 `0x5275` |

- **双频交叉验证**：CPI 1.5388 / 1.5387（0.006%）、cycles/iteration 差 0.075%、
  `CoreMark/MHz x1000` 均为 901 → 性能与频率无关，两点互为验证。
- 两次运行都满足 **官方四 CRC 全过 + `Correct operation validated.` + 运行 ≥10 s**（22.196 s / 34.682 s）。
- 本轮位流 SHA-256（前 16）：CoreMark 50 MHz `3791D1E7D91D90AC`、CoreMark 80 MHz PLL `34BA88F53FD0FF9C`、
  逻辑分析仪 50 MHz `17FD57D8F12FF4DC`、逻辑分析仪 80 MHz PLL `0388100A6D471402`。
  `rtl/pipeline_cpu.v` SHA-256 前 16：`8E8EB3A69B2EF45E` → **`BD8BA8640C3B6A4D`**。

### 时序（四个配置全部重新综合，全部 `All Constraints Met`）

| 工程 | WNS | WHS | 备注 |
|---|---:|---:|---|
| CoreMark 50 MHz | +2.349 ns | — | 最差路径 `core/rf/regs → imem/mem_7` |
| CoreMark 80 MHz PLL | **+0.667 ns** | +0.312 ns | 估计 Fmax **84.51 MHz**（上一轮 +0.145 ns） |
| 逻辑分析仪 50 MHz | +2.812 ns | — | |
| 逻辑分析仪 80 MHz PLL | **+0.789 ns** | — | 估计 Fmax **85.39 MHz** |

新增的“下一取指 PC → BTB → `if_req_pred_*`”组合链确实成为 80 MHz 最差路径，但余量反而比上一轮更大。

**频率扫描复核（CPI 优化后 RTL，`run_fmax_sweep_rtl.ps1 -Tag cpi3 -Periods '11.765,11.111'`）**：
**85 MHz `All Constraints Met`，WNS +0.393 ns、0 失败端点（改动前 +0.246 ns）**；
90 MHz 仍 VIOLATED（WNS −0.374 ns、102 失败端点）。芯片天花板仍约 **88～90 MHz**。
即「最高工作频率」计分项维持 **85 MHz（时序证据）/ 80 MHz（实体板实跑）** 不变，且余量变大。

### 逻辑分析仪应用（同一份 Core，位流全部重建）

| 配置 | 结果 |
|---|---|
| 50 MHz | `scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20` → **80/80 PASS**（static/counter/uart/spi 各 20 轮） |
| 80 MHz PLL | 同上 → **80/80 PASS** |

证据目录：`release/evidence/logic_analyzer_board_cpi50m/`、`logic_analyzer_board_cpi80m/`。

### 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 全套回归（含 CoreMark 三个入口） | `scripts\run_final_regression.ps1` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 官方 CoreMark RTL 仿真 On / Off | `run_coremark_pipeline_tb.ps1` / `-DisablePredictor` | cycles 1,852,156 → **1,295,932**（CPI 2.3747 → 1.6539）/ 2,106,042 → **1,604,264**（2.7143 → 2.0670） |
| 板级同源存储器模型 CRC 自检 | `run_coremark_fpga_tb.ps1` | `ALL COREMARK FPGA TOP TEST PASS`，cycles 1,221,446 |
| 实体板 CoreMark 50 MHz | `cdt_cfg` + `coremark_serial.py COM11` | PASS，Score 45.051、22.196 s、crcfinal `0xd340` |
| 实体板 CoreMark 80 MHz PLL | 同上，2500 迭代 | PASS，Score 72.081、34.682 s、crcfinal `0x5275` |
| 实体板逻辑分析仪 50/80 MHz | `run_logic_analyzer_board.ps1` | 各 80/80 PASS |

### 一处必须说明的测试期望更新

`scripts/run_pipeline_load_use_tb.ps1` 的 `EXPECT_LOAD_STALL` **3 → 4**：
测试程序含 4 组相邻 load-use，旧值 3 是“取指每两拍一条”时代的历史标定
（当时取指空洞恰好把 0x24→0x28 这对指令拉开两级）。逐事件探针与完整理由见
`docs/rtl_changes.md` §2.8 与 `docs/debug_log.md`。同一测试的提交级 trace 与最终状态对比全部 PASS。

### 下一步（下一轮候选）

1. **候选 A（收益最大）**：正确预测的跳转不再 Redirect。板级目前约 28,500 次/迭代属于
   “BTB 已预测正确但仍被 `idex_jump` 无条件 Redirect”，每次多花 3 拍 ≈ 7.7% cycles。
   前置条件：BTB 对 jump 的 `update_taken` 目前取自对 JAL/JALR 无意义的 `branch_unit`，需先改成恒 taken。
   预期 CPI 1.5388 → 约 1.42、Score 45.05 → 约 48.8。
2. 候选 B：数据访问 1 拍阻塞与取指重叠（上界 ≈ 7%，风险高）。
3. 已作废候选：原「数据事务 REQ→RSP 压一拍」被 T1 证伪（板级本来就只有 1 拍阻塞）。

### 已知遗留

- `release/artifacts/fmax_tuning_2026-09-17/` 与 `release/final_submission/` 内的位流是**上一轮**版本，
  本轮新位流并存于 `fpga/*/generate_bitstream/`。未静默替换发布清单；
  如需刷新发布包，必须按 `export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 顺序执行。
- `fpga/soc_demo`、`fpga/pipeline_soc` 的演示位流内嵌同一份 Core，本轮未重建。

---

## 上一轮：性能调优轮（2026-09-17，T0～T6）

本轮在赛题一评分规则范围内对最终版做了频率扫描、CPI 归因、关键路径提取和一处 RTL 优化，
并把 80 MHz PLL 配置做成可交付工程。完整数据见 `docs/performance_tuning.md`，
逐条改动说明见 `docs/rtl_changes.md`，CPI 归因见 `docs/coremark_cpi_analysis.md`。

### 关键结论（数据具体到数字）

1. **"松约束下的估算 Fmax"确实只是下界**。同一份 RTL、同一套配方，只改 `.fdc` 的 `create_clock -period`：
   50 MHz 约束报估算 Fmax 54.96 MHz，70 MHz 约束报 75.60 MHz，80 MHz 报 83.95 MHz，85 MHz 报 85.03 MHz。
   **PDS 的 `Estimated Frequency` 是"约束下反推值"，不能当作芯片上限。**
2. **真实天花板约 89～90 MHz**。优化前 90 MHz 失败（WNS −0.059 ns、TNS −0.455 ns、18 个失败端点），
   85 MHz 恰好通过（WNS **+0.005 ns**）。优化后 90 MHz 仍失败（WNS −0.148 ns、113 个失败端点），
   85 MHz 有 WNS **+0.246 ns**、80 MHz 有 +0.145 ns、70 MHz 有 +1.035 ns、50 MHz 有 +1.693 ns，
   所有实测点 hold WHS ≥ +0.276 ns、THS = 0。**回答用户问题：70 MHz 与 80–85 MHz 都达到；90 MHz 不达到。**
3. **公共瓶颈是性能计数器**。50 MHz 约束下最差 10 条路径有 8 条终点在 `perf/flush_count`，前 3 名全是
   `core/rf/regs/iGopDrm → exalu → N161.eq_* (16 级相等比较) → perf_mispredict → perf_flush (fanout=46) → flush_count[24..60] (10 级 CECO 进位链)`，
   26 级逻辑、arrival 22.789 ns。task30 逻辑分析仪配置是同一瓶颈（25 级、arrival 21.933 ns）。
4. **已落地改动只有一处**：`rtl/perf_monitor.v` 把 9 个事件先锁一拍再驱动计数器，
   切断"事件分类 → 64-bit 计数器进位链"的组合路径。效果：50 MHz 约束下 `perf/` 终点从最差 10 条中占 8 条降为 **0 条**，
   最差路径逻辑级数 26 → 21、逻辑延迟 8.381 → 7.866 ns；85 MHz 的 WNS 从 +0.005 提到 **+0.246 ns**。
   该模块是 Core 外只读统计逻辑，**端口与计数器宽度未变，不触及 Core/SoC 边界、流水线、Hazard、提交 trace 或 Reference Model**。
5. **提频率不会提 Score**。`Score = Iterations/(Total_Time × Frequency)` 等价于 CoreMark/MHz，是频率归一化的；
   提频率只服务于独立的第 (2) 项「时钟频率」。要提 Score 必须降 CPI。
6. **CPI 最大单项优化空间是访存事务等待**：RTL 仿真（官方 CoreMark、Predictor On）CPI 2.3747 中，
   访存相关合计约 **48% cycles、1.14 CPI**（理想执行 1.0000 / Hazard stall 0.2259 / 控制冒险 flush 0.2090 / 访存事务等待 0.9398）。
   把数据事务 `dstate` 的 REQ→RSP 两拍压成一拍估计可回收约一半（CPI 约 −0.4，约 −17%），
   但需要改动流水线访存时序，风险高于本轮改动，**本轮未做，作为下一轮明确建议**。
   板级 `cycle_count/instret_count`（2.2719）不能当 CoreMark 内核 CPI——`ticks` 与 `cycle_count` 窗口相差 18.6%。

### 80 MHz PLL 配置（新增可交付工程）

P20 是 50 MHz 固定晶振，>50 MHz 必须倍频；PGL50H PLL 只能整数分频，**无法精确产生 85/90 MHz，但能精确产生 80 MHz**：
`IDIV=1, FDIV=16, ODIV0=10 → PFD 50 MHz, VCO 800 MHz, 输出 80.000 MHz`（VCO 需在 600～1250 MHz 内）。

| 工程 | 顶层 | 80 MHz 时序 | LUT | FF | DRM18K | 位流 SHA-256 |
|---|---|---|---:|---:|---:|---|
| `fpga/coremark_80m` | `mes50hp_coremark_pll_top` | All Constraints Met，WNS +0.721 / WHS +0.312 | 3003 | 2593 | 33.0 | `3BF90440BDC9D2AB463B5D9E389107F846FB1A1A2972D81E03DA9070CC23948F` |
| `fpga/logic_analyzer_80m` | `mes50hp_logic_analyzer_pll_top` | All Constraints Met，WNS +0.652 / WHS +0.312 | 3781 | 3143 | 5.5 | `261D3989AC2D3EC686B9C740B42E988A96175B8534BE5F494D66573A1A54D898` |

PLL 原语 `GTP_PLL_E3` 直接例化在 `fpga/coremark_80m/rtl/pll_80m.v`，**不依赖外部 IP 文件**，完全位于 Core 之外。
UART 波特率按新时钟重算：80e6/115200 = 694 → 实际 115274 baud（−0.064%，在容差内）。
RTL 级闭环测试 `scripts/run_logic_analyzer_pll80_board_top_tb.ps1`（`tb/pll_80m_model.v` 提供 PLL 行为模型）输出
`PLL80 LOCK PASS` / `PLL80 FREQ PASS period_ps=12400` / `PLL80 UART PASS bytes=13` / `PLL80 CAPTURE PASS count=9` / `ALL TASK30 PLL80 BOARD TOP TEST PASS`。

### 官方 50 MHz 工程已用优化后 RTL 重建

| 工程 | 时序 | LUT | FF | 位流 SHA-256 |
|---|---|---|---:|---:|---|
| `fpga/coremark` | All Constraints Met，WNS +1.693 / WHS +0.314 | 2709 | 2585 | `9F42B8F9720D70471F2479D7DAE4F702BF60A22365223207D0BEED68AB596B26` |
| `fpga/logic_analyzer` | All Constraints Met，WNS +2.257 / WHS +0.319 | 3458 | 3137 | `DB705898A42BA25628303017034DDB7531DBA44BDBB58574E5CAFC19AAA331E6` |

调优前后位流与对应时序报告已归档到 `release/artifacts/fmax_tuning_2026-09-17/`（含调优前的逻辑分析仪位流存档 `la_50m_pre_tuning_ARCHIVE.sbit`，SHA-256 `2C09E690…`）。
**注意**：`release/final_submission` 与 `release/artifacts` 顶层的位流仍是调优前版本（`2C09E690…`），
其 `SHA256SUMS.txt` 因此仍然自洽；调优后位流是并存的新交付物，未静默替换发布清单。

### 本轮验证结果

| 验证 | 命令 | 结果 |
|---|---|---|
| 全套回归（20 个入口） | `scripts\run_final_regression.ps1 -Quick` | `ALL AUTOMATED FINAL REGRESSION PASS` |
| 性能计数器定向 + MMIO | `run_perf_monitor_tb.ps1` / `run_perf_mmio_tb.ps1` | 13/13、8/8 PASS（含 clear/disable 边界） |
| 官方 CoreMark RTL 仿真 | `run_coremark_pipeline_tb.ps1` | `cycles=1852156 retired=779952`，官方 CRC 全过，**与改动前逐字段一致** |
| 频率扫描（优化前 5 点 / 优化后 7 点，隔离目录） | `scripts\run_fmax_sweep_rtl.ps1` | 见上 |
| 80 MHz PLL 顶层 RTL 闭环 | `scripts\run_logic_analyzer_pll80_board_top_tb.ps1` | `ALL TASK30 PLL80 BOARD TOP TEST PASS` |
| 80 MHz 位流构建（两套工程） | PDS 完整流程 | `All Constraints Met`，0 失败端点 |

### 实体板验证：**已完成**（2026-09-17 补测，JTAG 下载线接上后）

扫描链确认 `Cable index 0: USB Cable II`、器件 `PGL50H`，每次下载 `The done bit is 1`。

| 验证项 | 位流 SHA-256 | 结果 |
|---|---|---|
| 优化后 50 MHz CoreMark | `8001A60D4CB17433` | **Score 29.559**、ticks 1,691,496,677、**33.829 s**、CPI 2.3443，四个官方 CRC 全过 + `Correct operation validated.` |
| 80 MHz PLL CoreMark | `FF6775A465A5CB68` | **Score 47.295**、ticks 4,228,738,028、**52.859 s**、CPI 2.3445，四个官方 CRC 全过 + `Correct operation validated.` |
| 逻辑分析仪 50 MHz 优化版 J8 回环 | `DB705898A42BA256` | static/counter/uart/spi 各 20 次 = **80/80 PASS** |
| 逻辑分析仪 80 MHz PLL 版 J8 回环 | `261D3989AC2D3EC6` | static/counter/uart/spi 各 20 次 = **80/80 PASS** |

**PLL 80 MHz 的独立交叉验证**：80 MHz 实测 1,691,495.2 周期/迭代，50 MHz 实测 1,691,496.7 周期/迭代，
相差 **0.0001%**；反推频率 4,228,738,028 / 52.859 s = **80.00 MHz**，与实测墙钟一致；
UART 按分频 694 输出全部正确，排除时钟错配。

**Score 频率归一化得到实体板证明**：29.559 × (80/50) = 47.295，两者 CoreMark/MHz 都是 **591**。

**测量口径修正**：原板级计数器窗口包含 `COREMARK_READY` 的 UART 轮询等待，导致 CPI 归因失真
（stall 甚至超过 cycles）。已在 `software/coremark/core_portme.c` 的 `start_time()` 加入
`PERF_CONTROL = 1u` 清零（`PERF_WINDOW_ALIGN=1` 开关，纯观测口径修正，不改执行路径）。
修正后 50/80 MHz 两点 CPI 分别为 2.3443 / 2.3445，逐项吻合到 0.02% 以内。

证据：`release/evidence/coremark_uart_opt50m_aligned.log`、`coremark_board_opt50m_aligned.json`、
`coremark_uart_80m_aligned.log`、`coremark_board_80m_aligned.json`、
`release/evidence/logic_analyzer_board_opt50m`、`release/evidence/logic_analyzer_board_80m`。

## 当前阶段

Task 20～32 的自动化 RTL/软件/PDS 证据已经通过，当前执行 Task 33～35 交付冻结。开发阶段的多套验证配置已经收口，发布入口只保留 `mes50hp_logic_analyzer_top` 一套最终配置：RV32I 五级流水线、16 项 BTB、UART/GPIO、十项性能计数器和八通道逻辑分析仪。官方 CoreMark CRC 与 Predictor Off/On 已通过 RTL 仿真；MES50HP JTAG 下载和 J8 四模式物理回环已完成实体验收，CoreMark 实体计分、Fabric Debugger 波形和断电压力仍按各自证据边界单独记录。

> 2026-09-17 接班交付包一致性修复：上一轮导出（08:37）早于当日 J8 隔行脚对约束校正、Capture Engine 分频边沿修复与上位机位中心采样修复（13:45～13:48），因此 `release/final_submission` 与 `release/artifacts` 内仍是旧位流 `01C39461…`，与实体板 80/80 回环所用 `2C09E690…` 不一致；`.fdc`、`README.md`、`reports/timing.rtr`、`rtl/capture_engine.v`、`rtl/logic_analyzer_pattern_gen.v` 与三份上位机工具同样是修复前版本，且包内缺少 `evidence/logic_analyzer_board_final`。已用 PowerShell 7.6.5 重新执行 `export_final_submission.ps1`（`FINAL SUBMISSION EXPORT PASS files=215`）、`create_release_manifest.ps1`（`RELEASE MANIFEST PASS files=1221`）与 `audit_release_package.ps1`（`RELEASE PACKAGE AUDIT PASS final_files=132 artifacts=3`）；最终位流三处副本 SHA-256 均为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。13 页技术报告 PDF 已归档到 `release/materials/technical_report.pdf`（与 `technical_report.docx` 同源渲染件，封面与末页已复核）。本轮未修改任何 RTL。

> 2026-09-17 接班回归复核：`run_final_regression.ps1 -Quick` 输出 `ALL AUTOMATED FINAL REGRESSION PASS`，20 个入口全部 PASS（Task 12/17/23/24/25/26/28/29/30/33 与最终 bitstream 哈希校验 `sha256=2C09E690…`）；Task 23 汇总入口现为 13 个，Task 30 board-top 与 SoC 集成、Python/VCD、冻结范围审计均 PASS。

> 2026-09-17 接班证据复核补充：官方 CoreMark 三项按正式入口重跑并 PASS——固定延迟 `cycles=1852156 retired=779952`、`predictor enabled=1 predict=213756 btb_hit=203492 mispredict=51908`，随机背压 `cycles=3339018`，FPGA memory model `cycles=1831176 bytes=655`；固定延迟结果与 `release/evidence/automated_metrics.json` 的 Predictor On 记录逐字段一致，证明该结论可在当前工作区复现。同时修复 `python/release_evidence.py` 的资源提取缺陷：原实现从 device map 段取 FF（3120）却从综合段取 LUT/DRM，现统一取综合统计 `Total Registers`（3129），并把布局布线后实现 FF 另存为 `ff_implemented=3120`，使自动证据与 `docs/progress.md`、`release/HANDOFF.md` 及技术报告的 3129 FF 一致。

> 2026-09-15 最新交付记录：修复流水线在数据事务等待期间 WB 值不再可转发导致的错误，新增 `wb_hold` 定向用例并将 Task 23 汇总扩为 10 个入口；Task 24 固定/随机背压的完整退休 trace、x1～x31 和关键 RAM 比较继续 PASS。官方 CoreMark checkout 固定到 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，固定/随机事务仿真均输出官方 CRC。同步 FPGA memory model 为 1,923,077 ticks/iteration、CPI 2.6682、CoreMark/MHz 0.520000；正式镜像为 1000 iterations、50 MHz、串口 `R` 启动，预期计时区间 38.46154 s，实体成绩尚不宣称。

> PDS 2026-09-15：Pipeline SoC 为 2267 LUT、1343 FF、1 DRM、setup WNS +6.062 ns、slow-corner hold +0.314 ns、estimated Fmax 71.7463 MHz；CoreMark 为 2438 LUT、1333 FF、33 DRM、setup +5.350 ns、hold +0.313 ns、estimated Fmax 68.2594 MHz；修正精确 pre/post 后的逻辑分析仪为 2998 LUT、1880 FF、7 DRM、setup +5.264 ns、hold +0.315 ns、estimated Fmax 67.8610 MHz。三者在 50 MHz 下均 All Constraints Met，指标由 `run_release_evidence.ps1` 自动提取。

> Task 30 2026-09-15：增加可编程 8 路物理回环发生器，支持静态、计数器、UART 8N1 和 SPI mode 0；正式固件采用 13 字节带 XOR 校验配置包，上电输出 `LA_READY`，无需重新综合即可更改模式、数据、速率、触发和前后采样。独立发生器 TB、MMIO byte-enable、20 轮采集/Reset 压力、交互式 board-top UART、AUTOSTART SoC、Python UART/SPI/VCD 六类入口全部 PASS。Capture Engine 进一步修正为精确 `pre + trigger + post` 计数和逻辑 trigger index，正式 Task 30 bitstream SHA-256 为 `C8123DA9699AE29D528F2FE61BFD8A3064DB678DB9AA1F0050EA490545BF779A`。

> 2026-09-17 实体约束校正：用户提供的实际 J8 约束使用隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`，原先连续 `3..18` 的文档与实体接线不一致。工程 `.fdc`、平台表、上位机提示和发布材料已按实际 LOC 同步；此前实体 static 出现 `期望 A5、实际 AF` 和 `期望 00、实际 AA`，根因是旧约束使 CH1/3/5/7 输入悬空，不作为逻辑功能失败证据。

> 2026-09-17 实体闭环完成：修复 UART pattern restart 的空闲帧同步、Python 位中心采样，以及 Capture Engine 在分频采样下每系统时钟更新 `previous_sample` 导致边沿丢失的问题；新增 `divided edge retained` 定向测试。最终位流经 PDS 2024.2-SP2 重建并 JTAG 下载，DONE=1。J8 实体回环 static、counter、UART 8N1 `0xA5`、SPI mode 0 `0x3C` 各连续 20 次，共 80/80 PASS；原始串口、JSON 和 VCD 位于 `release/evidence/logic_analyzer_board_final`。

> 2026-09-16 最终 RTL 完善：修复 `soc_fpga_dmem` 运行时写后读闭环；ALU 的 SLT/SRA 改为显式位逻辑；流水线加入 16 项直接映射 BTB 与 2-bit 饱和计数器，新增 prediction/BTB-hit/misprediction 计数和非法指令、未对齐、总线错误事件。预测器单元、别名替换、端到端恢复及错误可观测性测试均 PASS。相同 CoreMark 一次迭代镜像下，Predictor On 为 1,852,156 cycles，Off 为 2,106,042 cycles，减少 253,886 cycles（12.06%）；On 统计 213,756 次预测、203,492 次 BTB hit、51,908 次 misprediction。该结果为 RTL 仿真，不冒充实体成绩。

> 2026-09-17 唯一最终配置：不再把阶段性的 Pipeline、CoreMark 和 DebugCore 配置混入最终下载入口。`mes50hp_logic_analyzer_top` 已用最终 RTL、固件和 J8 隔行相邻脚对重新完成 PDS，50 MHz 下 All Constraints Met，慢角 setup/hold 裕量为 +2.661/+0.312 ns，估算 Fmax 57.6735 MHz，综合资源 3459 LUT、3129 FF、5.5 个 DRM18K 等效块；最终 `.sbit` SHA-256 为 `2C09E6904A6C6238CF7158E907087F905C1B7DF46E6D2C9B665E1DE10964746E`。

> Task 33 2026-09-16 最终收口：`run_final_regression.ps1 -Quick` PASS，覆盖 RV32I、Reference、Pipeline Hazard/Reset/Trace、GCC 等价、BTB、错误可观测性、性能计数器、官方 CoreMark、最终 SoC、逻辑分析仪与范围审计。`create_release_manifest.ps1` 和 `export_final_submission.ps1` 只导出唯一最终 bitstream、对应时序报告与固件镜像；开发阶段配置不再属于交付入口。

> Task 29 2026-09-15：用本机 PDS 许可证和官方 `DebugCore 1.4`/`Jtag_Hub 1.5` IP 生成独立诊断配置。`scripts/run_coremark_ila_pds.ps1` 自动生成 IP、同步 CoreMark 镜像、编译含 `PDS_COREMARK_ILA` 的顶层并完成 Compile→Synthesize→Place→Route→Timing→Bitstream；192-bit、512-sample probe 包含退休 PC/instruction、寄存器写回、Store、stall/load-stall、branch/taken/flush、请求握手和 reset。结果为 4416 LUT、4458 FF、39 DRM、setup WNS +5.453 ns、hold +0.186 ns，bitstream SHA-256=`B2F4C8A30A6207942786257AEFF9B35DF1DF1EA413F872DAC67E6BD0D5D24506`。Task 28 正式计分镜像不含 DebugCore；当前仅缺实体板下载后 Fabric Debugger 波形证据。

> Task 30 记录（2026-09-17）：`capture_engine.v`、`logic_analyzer_mmio.v`、`application_mmio_mux.v`、板级顶层/约束、可综合固件、RV32I 配置软件和 Python/VCD 工具均已通过自动化回归；J8 隔行相邻脚对的最终 PDS 已重建并满足 50 MHz 全部时序约束。自动化压力与实体板四模式各 20 轮均 PASS，G11 的 8 通道物理闭环证据已签署。

> Task 33～35 准备（2026-09-16）：最终回归、发布清单和复现说明已统一为一套最终配置。官方 CoreMark 源码、BTB Before/After、PDS 产物与最终压缩包均已具备；实体串口、物理回环和断电压力仍不以仿真或综合估算冒充。

> Task 18 完成记录（2026-09-14）：已在 `docs/architecture.md` 冻结 IF/ID、ID/EX、EX/MEM、MEM/WB 的字段、Bubble、MEM 等待和 EX redirect/错误路径响应丢弃的时序约定；在 `docs/interfaces.md` 冻结 `pipeline_cpu` 模块名、复用的通用取指/数据事务端口、提交 trace 和通用性能事件端口。`./scripts/run_pipeline_smoke_tb.ps1` 对 Task 11 程序 PASS，证明候选 Core 的五级基本数据流可运行。当前 `rtl/pipeline_cpu.v` 含有尚未独立验收的 Forwarding、Load-Use Stall 与 Flush 逻辑，不能作为 Task 20～22 或 G7/G8 完成证据；Task 19 必须新增人工 NOP 的独立无 Hazard 程序，并与 frozen single-cycle Reference 自动比较 x1～x31、关键 RAM 及完整提交 trace。

> Task 19 完成记录（2026-09-14）：`tb/data/no_hazard.mem` 在每个 RAW producer/consumer 间插入三条 NOP。`run_pipeline_no_hazard_tb.ps1` 分别在固定延迟及候选 Pipeline 的随机取指/数据背压条件下，逐字段比较前 17 条退休 trace，并比较 `x1`～`x31`、`RAM[0]`；两种模式均 17/17 PASS。Task 19 / 无 Hazard 五级数据通路通过；下一步进入 Task 20。该测试没有用来证明任何 Forwarding、Load-Use 或 Flush 行为。

> Task 20 阶段记录（2026-09-14）：已新增独立 `rtl/forward_unit.v`，并在候选流水线 EX 操作数路径中使用。`run_forward_unit_tb.ps1` 的 9 项选择、优先级、Load 排除、x0 和错误响应测试 PASS；真实相邻/间隔 ALU RAW、双源、同 rd 优先级和 ALU→Store 的 Reference trace 回归已由 Task 20～23 汇总入口覆盖。

> Task 20～23 完成记录（2026-09-14）：Forwarding 端到端镜像覆盖一级/二级、双源、同 rd 优先级、x0 与 ALU→Store；Load-Use 覆盖 Load→ALU/Store/Branch，并在固定时序下精确产生 3 次额外 Bubble（另一个依赖由数据事务整体等待覆盖，无需重复 Stall）；Control Hazard 覆盖 taken/not-taken Branch、JAL/JALR、link 依赖和错误路径 Store；交叉压力覆盖 ALU/Load→Branch/Store、错误 Load/Store 响应、固定/随机背压、请求字段稳定、Store 单次副作用和 Reset 中止。修复了 IF 因原 adapter 空泡未真实激活 Hazard，以及 Redirect 撤回受背压取指 valid 两个问题。`run_pipeline_regression.ps1` 汇总 9 个入口；全部 PASS 后 Task 23 / G8 通过，允许进入 Task 24。

> Task 24 完成记录（2026-09-14）：`run_gcc_pipeline_equivalence.ps1` 自动构建并运行 Task 14 的 `c_smoke` 与 `array_control` 两个真实 RV32I GCC 程序；固定/随机取指和数据延迟共四组均通过，77/71 条提交 trace 逐字段与 Task 17 golden 一致，最终状态一致。Pipeline 运行分别记录 259/454 与 214/399 cycles。GCC Pipeline / G9 软件前置通过。

> Task 25 完成记录（2026-09-14）：新增 Core 外 `perf_monitor` 七项 64-bit 计数器与 `perf_mmio` 只读窗口/CONTROL 清零接口。`run_perf_monitor_tb.ps1` 覆盖 cycle、instret、stall、load-stall、branch、taken、flush、Reset、clear、disable；`run_perf_mmio_tb.ps1` 覆盖低/高字、错误 offset 和清零写，均 PASS。Task 24 GCC Pipeline 已接入计数器并输出 perf evidence；计数器不修改 Core/流水线端口。

> Task 26/27 阶段记录（2026-09-14）：`fpga/pipeline_soc` MES50HP Pipeline SoC wrapper 仿真通过，复用统一互连、UART/GPIO、性能计数器和同一 Pipeline Core；`run_mes50hp_pipeline_soc_tb.ps1` 通过连续 UART 双行、LED=0xAA 和 50 MHz wrapper 仿真。命令行 PDS 因 `Flow-0183` 许可证变量缺失而阻塞，实体板 Pipeline 下载尚未取得证据，故 G9 尚未完成。

> Task 15 完成记录（2026-09-12）：单周期 Core 已移除内部 IMEM/DMEM，新增并验证 `i_req_*` / `i_rsp_*` 与 `d_req_*` / `d_rsp_*` 单 outstanding 事务端口；`IF_REQ`/`IF_RSP`/`IF_DONE` 与 `MEM_RUN`/`MEM_REQ`/`MEM_RSP` 在随机取指/数据背压下 PASS。`soc_data_interconnect` 的 RAM/UART/GPIO/Application/未映射地址译码定向测试 PASS；Core→取指 adapter→Core→互连→外部 RAM 集成测试 PASS。历史 Task 12 全量、Task 13 提交 trace、Task 14 GCC 两项均已通过外部 adapter harness 迁移回归。Task 15 Gate 通过；真实 UART/GPIO wrapper 属于下一任务 Task 16。

> Task 16 阶段记录（2026-09-13）：`gpio_mmio` 独立测试 63/63 PASS。UART 已完成 `UART_TX`（15/15 PASS）、8N1 `UART_RX`（正常帧、假起始位、错误停止位、连续帧共 11/11 PASS）及 `uart_mmio`。UART 地址窗口内现定义 `TXDATA=0x00`、`STATUS=0x04`、`RXDATA=0x08`：`RXDATA` 为单字节阻塞读取邮箱，`STATUS[0]` 为 TX ready、`[1]` 为 TX busy、`[2]` 为 RX valid、`[3]` 为 sticky RX overflow、`[4]` 为 sticky frame error，后两位可由 `STATUS` 写 1 清除。TX MMIO 36/36 PASS，RX 邮箱/MMIO 23/23 PASS。真实 UART/GPIO 从设备接入冻结的 `soc_data_interconnect` 后，通用 CPU 事务的 GPIO 写、UART TX、TX busy 读取、UART RX 状态/读取均 20/20 PASS。`tb/tb_soc_harness.v` 进一步使未修改的 `single_cycle_cpu` 实际执行 `software/mmio_demo/build/mmio_demo.mem`；取指 ROM 与数据 RAM 均按链接脚本预加载同一 1 KiB 镜像，CPU 在 2676 个时钟内写出 GPIO=`0xAA`，并由独立 `UART_RX` 线路观察器无帧错误解码 `Hello RISC-V!\r\n`。运行 `./scripts/run_soc_harness_tb.ps1` 为 19/19 PASS。已新增 `fpga/soc_demo`：MES50HP board wrapper、P20/R8/R9/8 个 LED 的真实 `.fdc`、同一程序镜像的取指/数据 RAM 和 PDS 实现配方；`./scripts/run_mes50hp_soc_demo_tb.ps1` PASS，验证上电复位、LED=`0xAA` 和 UART 线路输出。为避免板上串口晚打开而错过单次输出，demo 现在在发送完整 `Hello RISC-V!\r\n` 后持续循环；镜像和综合常量已同步更新。PDS 重新完成 Compile→Synthesize→Place→Route→Timing→Bitstream，新 bitstream 为 `generate_bitstream/mes50hp_soc_demo_top.sbit`，无 `$readmemh` 警告，50 MHz 目标下预计 59.0179 MHz、WNS=3.056 ns、TNS=0。实体板已通过 CP2102 串口完成 UART 验收：115200、8N1、无流控下持续输出 `Hello RISC-V!`。当前可工作的 PDS 管脚映射为 `uart0_tx=R9`、`uart0_rx=R8`；此前无串口输出的根因是未连接独立 USB-UART 数据线。GPIO 的实体 LED 已确认呈现高有效 `0xAA` 模式（LED2、LED4、LED6、LED8 亮）。Task 16 的仿真与实体板验收均已完成，G5 通过。

> Task 17 完成记录（2026-09-13）：`run_single_cycle_reference_regression.ps1` 已接入独立 RAM+GPIO、RAM+UART 与 Task 14 GCC evidence suite。完整入口连续两次均为 14 passed、0 failed；所有系统程序的最终状态、性能和提交 trace golden 均匹配。比较器已验证可对 `rd_data` 与 Store `mem_data` 篡改报告字段级首差、PC 和 instruction。Task 17 / G6 已通过，允许进入 Task 18。当前版本具备创建 `single_cycle_stable` 标签的条件，但该标签尚未创建。

> 平台迁移：正式 FPGA 已由在线 DUT 切换为盘古 50（MES50HP）`PGL50H-6IFBG484`。此前记录的 PG2L200H、S2/S3、27 MHz、`D18`、`AC26`、`AB26` 和在线下载结果只保留为历史实验记录，不能作为当前 Gate 证据。当前目标、已确认管脚和待验证项以 `docs/fpga_platform.md` 为准。

## 已完成

- [x] 项目基线与核心文档建立
- [x] 赛题需求分析
- [x] CPU 基础概念
- [x] 按 2026 紫光同创 RISC-V 赛题重新校准任务顺序和 Gate
- [x] 确立 CPU Core / SoC 外设解耦原则并建立 `docs/interfaces.md` 接口契约
- [x] 选定“可重构多协议逻辑分析仪”应用并建立功能、MMIO、验证和量化指标规格
- [x] 固定报名作品名称“RISC-V多协议逻辑分析仪”（14/15字符）和436字符作品简介（2026-09-17 改为 B 版叙事稿：偏应用闭环叙事、不含具体量化数字）
- [x] 根据官方赛题页建立 `docs/competition_scoring.md`，明确基础、性能、应用、文档和高阶任务映射
- [x] 冻结最终范围：基础项、16 项 BTB 和官方性能指标全保留，应用固定 8 通道 Raw P0 闭环，RLE 移至赛后研究
- [x] 在项目根目录初始化本地 Git 仓库，默认分支为 `main`，并建立首版 `.gitignore`
- [x] 从本届路线删除Cache/burst、完整异常中断、AI、DDR/HDMI/PCIe/千兆网、自定义指令及逻辑分析仪扩展项
- [x] 冻结本届正式 FPGA 平台为盘古 50（MES50HP）`PGL50H-6IFBG484`；50 MHz、CP2102 UART、按键/LED 及扩展 I/O 的已确认信息已归档
- [x] RV32I 指令格式
- [x] GCC 工具链与 Task 3 软件到机器码学习验收
- [x] Register File：学习者完成 `rtl/regfile.v` 的 32 × 32-bit、双组合读、单同步写与 `x0` 双层保护；`tb/tb_regfile.v` 的 10 项独立测试全部 PASS（2026-09-03）。
- [x] ALU：学习者完成 `rtl/alu.v` 的 10 种基础整数运算；31 项独立定向测试全部 PASS，并完成补码回绕、signed/unsigned 比较、逻辑/算术右移及移位量低 5 位解释验收（2026-09-03）。
- [x] Immediate Generator：学习者完成 `rtl/imm_gen.v` 的 I、S、B、U、J 五类立即数生成；Agent 编写独立 Testbench 和运行入口，25 项定向测试全部 PASS，并完成位重排、符号扩展、B/J 对齐和默认安全值解释验收（2026-09-04）。
- [x] Decoder / Control Unit：学习者完成 `rtl/decoder.v`，能够依据 `opcode`、`funct3`、`funct7` 译码 R-Type、I-Type ALU、Load、Store、Branch、JAL/JALR、LUI/AUIPC，并对非法/未实现编码保持无寄存器、内存或控制流副作用；Agent 编写独立 Testbench 和运行入口，64 项定向测试全部 PASS（2026-09-07）。
- [x] Branch Unit：学习者完成 `rtl/branch_unit.v`，支持 BEQ、BNE、BLT、BGE、BLTU、BGEU，并通过符号位与无符号比较正确实现 signed 比较；Agent 编写独立 Testbench 和运行入口，32 项定向测试全部 PASS（2026-09-07）。
- [x] Load / Store 数据处理：实现 `rtl/load_store_unit.v`，支持 `LB/LBU/LH/LHU/LW` 的 lane 选择与扩展，以及 `SB/SH/SW` 的 lane 对齐写数据与 `wstrb`；非对齐访问检测为 `misaligned=1`，并禁止 Store 写入。独立 Testbench 35/35 PASS（2026-09-07）。
- [x] Task 10 Memory + FPGA Gate：学习者完成 `rtl/dmem.v` 与 `rtl/imem.v`；DMEM 14/14、IMEM 12/12 独立测试 PASS，并确认 GNU objcopy 生成的真实 Verilog 程序镜像可由 `$readmemh` 直接加载（2026-09-08）。MES50HP `PGL50H-6IFBG484` PDS 工程以 `P20` 50 MHz 时钟、`B2` 高有效 LED1 完成实现，`GTP_DRM36K_E1` 1K×32 BRAM 映射确认；同一 bitstream 已通过 JTAG 下载两次，LED1 两次均点亮。Task 10 / G2 正式 PASS（2026-09-10）。
- [x] Task 11 最小单周期 CPU：学习者完成 `rtl/single_cycle_cpu.v`，将 PC、IMEM、Decoder、ImmGen、RegFile、ALU、Branch Unit、Load/Store Unit、DMEM、WriteBack 与 PC 选择器集成为单周期数据通路。独立 Testbench 以包含 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL` 的程序执行验证；检查 `x1=5`、`x2=10`、`x3=15`、`x4=15`、`x5=10`、`x6=0`、`x7=40`、`dmem[0]=15`、`dmem[1]=10` 与最终 `PC=48`，10/10 PASS，并具有 500 ns 超时保护（2026-09-11）。学习者已完成状态更新、访存地址/数据分离、BEQ 比较/跳转目标分离及 JAL 双路径的逐周期解释验收；Task 11 / G3 正式 PASS。

## 当前工具与平台状态

- 仿真器：Icarus Verilog 12.0 Windows 稳定包安装于 `D:\Tools\iverilog-v12`，当前仿真脚本默认使用且 Task 4～10 当前基础模块回归 PASS。OSS CAD Suite 内置的 14.0 development 版 `vvp.exe` 在 2026-09-07 出现启动级应用程序崩溃，已停用并记录于 `docs/debug_log.md`。
- RISC-V GCC：xPack GNU RISC-V Embedded GCC 15.2.0，安装于 `D:\Pango\toolchains\xpack-riscv-none-elf-gcc-15.2.0-1`；前缀为 `riscv-none-elf-`，`RISCV_PREFIX` 与 PATH 已配置。
- RISC-V 工具链验证：使用 `-march=rv32i -mabi=ilp32` 成功完成 C 编译、链接、反汇编以及 BIN/IHEX 生成；输出为 ELF32 little-endian RISC-V，`rv32i/ilp32/libgcc.a` 存在。
- GNU Make：xPack Windows Build Tools 4.4.1，安装于 `D:\Tools\xpack-windows-build-tools-4.4.1-3`，已通过实际 Makefile 构建验证。
- PDS：2024.2-SP2-EN，安装于 `D:\Pango\PDS_2024.2-SP2`；`pds_shell -version` 验证通过，PATH 已配置。MES50HP PDS/BRAM/JTAG/LED1 冒烟已完成，Task 10 / G2 PASS；SPI Flash 固化另行处理。
- Python/串口：Python 3.13.15 位于 `D:\Python313`；pySerial 3.5 位于 `D:\Python313\Lib\site-packages`，导入和串口枚举验证通过。
- Python D 盘约束：`PYTHONUSERBASE=D:\PythonUser`、`PIP_CACHE_DIR=D:\PythonCache\pip`，后续用户包与缓存固定到 D 盘。
- 目标 FPGA/平台：已冻结为盘古 50（MES50HP），器件为 `PGL50H-6IFBG484`；系统时钟 `FPGA_GCLK_50M=P20` 为 50 MHz（20.000 ns），约束格式 `.fdc`。
- UART：板载 CP2102，实体板已验证 RX=`R8`、TX=`R9`；115200、8N1、无流控下持续输出 `Hello RISC-V!`。此前无输出的根因是未连接独立 USB-UART 数据线，而不是 FPGA 管脚或波特率。
- Reset/I/O：默认 `USE_EXTERNAL_RESET=0` 使用内部上电复位；底板 `REST` 经 J4 Pin14 连接专用固件重加载电路，不作为普通用户 I/O。8 个用户按键低有效、8 个用户 LED 高有效，全部管脚与 3.3 V 电平已归档于 `docs/fpga_platform.md`。
- 固定编译目标：`-march=rv32i -mabi=ilp32`。
- 详细工具版本、路径、校验值和验证结果见 `docs/toolchain.md`。

## 当前稳定 RTL

- `rtl/regfile.v`：Register File 独立测试 10/10 PASS。
- `rtl/alu.v`：ALU 独立定向测试 31/31 PASS，Task 5 Gate 已通过。
- `rtl/imm_gen.v`：Immediate Generator 独立定向测试 25/25 PASS，Task 6 Gate 已通过。
- `rtl/decoder.v`：Decoder 独立定向测试 64/64 PASS，Task 7 Gate 已通过。
- `rtl/branch_unit.v`：Branch Unit 独立定向测试 32/32 PASS，Task 8 Gate 已通过。
- `rtl/load_store_unit.v`：Load / Store 数据处理独立定向测试 35/35 PASS，Task 9 Gate 已通过。
- `rtl/dmem.v`：行为级 DMEM 组合读、同步 byte-enable 写和越界保护独立测试 14/14 PASS；Task 10 Memory 阶段已纳入正式 Gate。
- `rtl/imem.v`：行为级 IMEM 组合读、对齐/越界保护、零初始化和 `$readmemh` 程序初始化独立测试 12/12 PASS；Task 3 的真实 `hello.mem` 已成功读回。
- `rtl/single_cycle_cpu.v`：Task 11 最小单周期 CPU，集成 Testbench 10/10 PASS；覆盖 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ` 与 `JAL` 的最小数据通路与控制流，Task 11 / G3 已通过。Task 12 的 FENCE/非法 SYSTEM 边界整机测试 32/32 PASS。
- Task 13 候选 Reference 观察：`rtl/single_cycle_cpu.v` 保持上述 ISA 行为，并输出只读提交级 trace；`tb/tb_single_cycle_reference_trace.v` 验证 10 条退休记录以及候选实例间的 `x1`～`x31`/关键 DMEM 一致性。该版本不是最终 `single_cycle_stable`。
- `fpga/bram_smoke/rtl/bram_smoke_top.v`：1024×32 同步 BRAM 自检核心，PDS 映射为 `GTP_DRM36K_E1`，实体 LED1 自检 PASS。
- `fpga/mes50hp_bram_smoke/rtl/mes50hp_bram_smoke_top.v`：MES50HP board wrapper，固定 `P20` 50 MHz 与 `B2` 高有效 LED1。

## 当前 Regression

- Task 20～23 / G8：`./scripts/run_pipeline_regression.ps1` 汇总 Forward Unit、Hazard Unit、无冒险、Forwarding、Load-Use、Control Hazard、复杂 Hazard、Reset 中止和旧 smoke 共 9 个入口。提交级比较覆盖固定/随机背压；压力程序 20/20 trace PASS，合法 Store trace 与 RAM side effect 均恰好 2 次，错误路径/错误响应无副作用。Reset 测试证明未接受 Store 被中止、重启后只产生一次写入。

- Task 30 本地 Regression：`run_capture_engine_tb.ps1`、`run_logic_analyzer_tb.ps1`、`run_application_mmio_mux_tb.ps1`、`run_logic_analyzer_soc_tb.ps1`、`run_logic_analyzer_board_top_tb.ps1`、`run_logic_analyzer_python.ps1` 全部 PASS；Task 30 板级顶层仿真使用综合可见 Task 30 固件常量，UART 前缀、GPIO=0x5A、Raw count=10 和 trigger_index=4 均通过。
- Task 28/29 性能证据：官方 CoreMark fixed/random 与同步 FPGA memory model 均验证官方 CRC；仿真估算 CoreMark/MHz=0.520000、CPI=2.6682、正式 CoreMark 配置 estimated Fmax=68.2594 MHz、2438 LUT。Task 29 DebugCore 配置为 4416 LUT、4458 FF、39 DRM、setup/hold WNS=+5.453/+0.186 ns。所有数值分别标注“RTL 仿真估算”或“PDS 综合/布局布线结果”，实体成绩与 Fabric Debugger 波形尚未宣称。
- Task 33～35 本地准备：所有历史含 `exit` 的子脚本均在独立 PowerShell 子进程中运行；2026-09-16 `run_final_regression.ps1 -Quick` 与 `run_scope_audit.ps1` PASS，四份 bitstream 均纳入产物存在性与 SHA-256 检查。新增 `release/board_validation` 自包含板级包（4 个 PDS 工程、共享 RTL/约束/DebugCore IP、4 份 `.sbit`、PyUI 和串口工具），并生成 `MES50HP_board_validation_package.zip`；`audit_board_validation_package.ps1` 检查通过。完整 `competition_final` 仍被实体板 CoreMark、Fabric Debugger、物理回环和断电压力证据阻塞。
- Task 34 候选材料：已生成 13 页技术报告 DOCX/PDF、12 页答辩 PPTX、三分钟视频脚本、答辩问答稿和现场恢复卡。DOCX/PDF 已逐页渲染检查；PPTX 已通过 12 页版式、SimHei 字体、3 个原生表格、1 个原生图表、包完整性和重新导入检查，并逐页检查渲染图。所有自动性能数字均注明 RTL 仿真估算或 PDS 结果，实体证据位置明确保留为待补，未宣称 Task 34/35 最终完成。

- Task 19 无 Hazard 基线：`run_pipeline_no_hazard_tb.ps1` 固定/随机延迟下 17/17 trace、x1～x31 和 RAM 状态 PASS；后续 Task 20～23 单独覆盖 Hazard、错误响应和 Reset，不混淆基线证据。

- Task 2 学习验收 PASS：可借助 RV32I 格式模板拆解 R、I、S、B、U、J 六类指令；正确解释 `lw`、`sw`、`bne`、`lui`、`jal`、`jalr` 的主要语义，以及 B/J immediate 的位重排、符号扩展和最低位对齐规则。
- Task 3 学习与构建验收 PASS：完成最小裸机 C 程序、`_start`、链接脚本和 Makefile；使用 `make clean; make all` 生成 ELF、反汇编、BIN、IHEX、Verilog IMEM 初始化文件，并通过 RV32I-only ISA 检查。已能解释 C → ELF → objdump/objcopy → IMEM → `_start` → `main` 的执行链路，以及 `jal`、`jalr`、`bne`、`sw` 的实际作用。
- Task 5 PASS：运行 `.\scripts\run_alu_tb.ps1`，ADD、SUB、AND、OR、XOR、SLL、SRL、SRA、SLT、SLTU、默认控制及关键边界共 31/31 PASS；学习者能够解释补码回绕、signed/unsigned 比较、逻辑/算术右移以及 `b[4:0]` 移位量规则。
- Task 6 PASS：运行 `.\scripts\run_imm_gen_tb.ps1`，I/S/B/U/J 类型的零值、正负数、边界值、B/J 最小对齐偏移、多个共享格式 opcode 和默认安全值共 25/25 PASS；学习者能够解释立即数位重排、符号扩展、B/J 最低位补零以及组合逻辑必须覆盖默认输出的原因。
- Task 7 PASS：运行 `.\scripts\run_decoder_tb.ps1`，R-Type、I-Type ALU、Load、Store、Branch、JAL/JALR、LUI/AUIPC 及非法/未实现编码共 64/64 PASS；学习者能够解释主译码与完整合法性检查、`RegWrite`/Memory/Branch/Jump 副作用抑制、ALU A/B 来源和 ALU/Memory/`PC+4`/Immediate 写回选择。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64 Regression，全部 PASS。
- Task 8 PASS：运行 `.\scripts\run_branch_unit_tb.ps1`，BEQ、BNE、BLT、BGE、BLTU、BGEU、相等/不等、正负数、signed/unsigned 极值差异及非法 `funct3` 共 32/32 PASS；学习者能够解释异号时由符号位决定 signed 大小、同号补码可直接比较，以及 `0xFFFFFFFF` 在 signed/unsigned 下的不同结果。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32 Regression，全部 PASS。
- Task 9 PASS：运行 `.\scripts\run_load_store_unit_tb.ps1`，覆盖五种 Load 的全部 byte lane、符号/零扩展、两种 halfword、三种 Store 宽度与 byte enable、所有当前定义的非对齐访问、非法 `funct3` 和空闲安全默认值，共 35/35 PASS。随后运行 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32 与 Load/Store 35/35 Regression，全部 PASS。
- Task 10 行为级 Memory 阶段 PASS：学习者完成 `rtl/dmem.v` 与 `rtl/imem.v`，能够解释字节地址到 word index/byte lane 的转换、`SB/SH/SW` 与 `wstrb`、组合读/同步写、指令对齐和 `$readmemh` 初始化。运行 `.\scripts\run_dmem_tb.ps1` 为 14/14 PASS；运行 `.\scripts\run_imem_tb.ps1`，连续取指、空 Memory 清零、非对齐/越界保护、手工初始化文件和 GNU objcopy 真实 `hello.mem` 共 12/12 PASS。随后使用 Icarus 12 稳定包重跑 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store 35/35、DMEM 14/14、IMEM 12/12，全部 PASS。新增最小 PDS BRAM 冒烟工程 `fpga/bram_smoke`：同步读 RAM 的上电复位、写入、隔拍读回和低有效 LED PASS 指示经 `.\scripts\run_bram_smoke_tb.ps1` PASS。该行为级记录保留为历史细节；MES50HP 硬件 Gate 结果见下一条。
- Task 10 MES50HP 硬件 Gate PASS：PDS 目标为 `PGL50H-6IFBG484`，使用 `P20` 50 MHz 与 `B2` LED1；`GTP_DRM36K_E1` 1K×32 BRAM 映射已确认。相同 bitstream 已通过 JTAG 下载两次，LED1 两次均点亮，证明内部上电复位、BRAM 自检和板级约束具有重复性。首次尝试的 SPI Flash 扫描报 `JtagServer-0335` / `Configuration-0008`，但这只影响持久化 Flash 固化，不阻塞临时 JTAG FPGA 冒烟；Task 10 / G2 正式 PASS（2026-09-10）。
- Task 11 / G3 PASS：运行 `./scripts/run_single_cycle_cpu_tb.ps1`，程序镜像 `tb/data/single_cycle_smoke.mem` 从 Reset PC=0 连续取指，覆盖 `ADDI`、`ADD`、`SUB`、`LW`、`SW`、`BEQ`、`JAL`，检查 7 个寄存器状态、两处 DMEM 状态和最终 PC 共 10 项，全部 PASS；Testbench 具备 500 ns 超时保护。随后重跑 RegFile 10/10、ALU 31/31、ImmGen 25/25、Decoder 64/64、Branch Unit 32/32、Load/Store 35/35、DMEM 14/14、IMEM 12/12 Regression，全部 PASS（2026-09-11）。学习者已完成关键状态与数据流的逐周期解释验收。
- Task 12 / G4 PASS：采用 RISC-V Unprivileged ISA `v20240411` 的 RV32I Base Integer ISA `Version 2.1`。已审查并修复 JALR target bit 0 清零，完成 U-Type、所有 R/I-Type ALU、五种 Load、三种 Store、六类 Branch、JAL/JALR 与自然对齐策略的定向整机验证；系统类边界冻结为合法 `FENCE` 的保守 no-op，以及 `FENCE.I`、ECALL、EBREAK、CSR 和未支持编码的 `illegal=1` 无副作用策略。`docs/rv32i_instruction_coverage.md` 已覆盖全部目标指令、边界、上游测试和不适用项。固定提交的上游 `riscv-tests` 中，RV32UI Core 29/29 PASS、Memory 10/10 PASS；统一入口 `./scripts/run_rv32i_regression.ps1` 包含 22 个测试入口、逐项失败退出，用户本地 PowerShell 已输出最终 `ALL TASK12 REGRESSION PASS`（2026-09-12）。允许进入 Task 13；本阶段仅建立候选 Reference Model，不得称为或冻结为 `single_cycle_stable`。
- Task 13 / G4 PASS：建立 `single_cycle_reference_candidate`，在 `rtl/single_cycle_cpu.v` 增加只读提交级 trace：`valid`、`pc`、`instruction`、寄存器写回和 Store 的原始字节地址、lane 对齐写数据及 byte enable。`tb/tb_single_cycle_reference_trace.v` 检查固定程序的 10 条退休记录（含 Load、Store、Branch、JAL）、`x1`～`x31` 和关键 DMEM，并确认故意改变 `rd_data` 会报告第一条不一致字段。`./scripts/run_single_cycle_reference_trace_tb.ps1` PASS；`./scripts/run_single_cycle_regression.ps1` 连续两次运行 trace 测试和 Task 12 全量 Regression。该版本不是 `single_cycle_stable`；GCC、统一事务接口、MMIO/UART/GPIO 和 Task 17 正式冻结仍未开始。
- [x] Task 14 / GCC 裸机程序 PASS：新增可重复的 `./scripts/run_c_program_regression.ps1`，固定使用 `-march=rv32i -mabi=ilp32 -O1`，自动检查反汇编不含未声明 ISA 扩展。`c_smoke` 验证启动栈、函数调用/返回、循环与 `.bss`，在复位前注入垃圾值后确认启动代码清零 `.bss`，最终 `result=45`。`c_array_control` 验证 `.data` 预加载、`.bss` 清零、局部数组、函数调用、两段循环及 `if/else` 真/假分支，最终 `seed=3`、`result=18`、`false_result=-1`。两项程序及全部自动断言 PASS（2026-09-12）；详细加载约定见 `docs/gcc_programs.md`。允许进入 Task 15；候选 Reference 仍不是 `single_cycle_stable`。
- [x] Task 15 / Core-Soc 数据接口、取指接口、地址译码与外部 adapter PASS：`i_req_*`/`i_rsp_*`、`d_req_*`/`d_rsp_*` 端口及单 outstanding 等待状态已接入；RAM/UART/GPIO/Application/未映射区域地址范围已冻结并完成互连定向测试；随机取指/数据背压、请求字段稳定、一次写一次副作用及 Core→互连→外部 RAM 集成全部 PASS。Task 12 29+10 项 RV32UI、Task 13 trace、Task 14 GCC 两项均通过迁移后的外部 adapter harness。Task 15 Gate 通过；下一目标为 Task 16 真实 GPIO/UART wrapper。

## 当前已知问题

- **实体板验证已完成（2026-09-17）**：JTAG 下载线接上后，优化后 50 MHz 与 80 MHz PLL 两套 CoreMark 位流
  均已在实体板复测通过（Score 29.559 / 47.295，33.829 s / 52.859 s，CRC 全过），两套逻辑分析仪位流
  各 80/80 J8 回环 PASS。详见上文「实体板验证」小节与 `docs/performance_tuning.md` §5.4。
- **发布包仍是调优前位流**：`release/final_submission` 顶层指向 `2C09E690…`，其清单自洽；
  调优后位流归档在 `release/artifacts/fmax_tuning_2026-09-17/` 并已通过实体验证。
  若要提升为正式发布版本，必须按顺序执行
  `scripts\export_final_submission.ps1` → `scripts\create_release_manifest.ps1` → `scripts\audit_release_package.ps1`（均需 pwsh 7）。
- **性能计数器窗口口径**：板级七项计数器必须用 `PERF_WINDOW_ALIGN=1` 镜像采集，否则 `COREMARK_READY`
  的 UART 轮询等待会污染计数（stall 甚至超过 cycles）。历史 `release/evidence/coremark_board.json`
  即为此种失真数据，仅 `ticks`/`score` 字段仍然有效，**不得**用它做 CPI 归因。
- **PDS 布局布线不具确定性**：同一 RTL 重复构建的 WNS 可差约 ±0.3 ns；所有 Before/After 结论都在同一批扫描内比较，
  并记录 RTL/FDC SHA-256，禁止跨批次混用数值。
- **85 MHz 零余量点**：调优前 85 MHz 的 WNS 仅 +0.005 ns，属"能过但不可用"；调优后为 +0.246 ns。
  选用 85 MHz 实跑需先完成实体板验证（且需 PLL 或外部时钟源，因为 P20 固定 50 MHz）。
- D3 硬件平台决策和 Task 10 Memory/FPGA Gate 已完成；MES50HP BRAM、`.fdc`、内部上电复位、JTAG 下载与 LED1 冒烟均已两次 PASS。SPI Flash 扫描/固化仍未完成，但它不是本次临时 JTAG 冒烟或 Task 10 Gate 的阻塞项。
- 历史在线 DUT 的 `Top.fdc`、器件和报告仅作为旧平台实验归档，已不再写入 `docs/fpga_platform.md`，也不得用于当前 PDS 工程、约束或 Gate 结论。当前工程必须复核 `PGL50H-6IFBG484`，不得沿用旧平台器件或管脚。
- PDS 批处理许可证路径可通过 `-LicenseFile` 或 `PANGO_LICENSE_FILE` 提供；当前四套工程均已完成批处理实现并生成 bitstream。许可证文件属于本机外部依赖，不进入仓库或发布包。
- MES50HP 手册已经确认实际使用接口的管脚和 3.3 V 电平；后续 `.fdc` 直接采用 `docs/fpga_platform.md` 的冻结映射。下载阶段只需通过板载 JTAG 实测 PDS 流程，不再把“缺少管脚/电压资料”列为阻塞项。
- OSS CAD Suite 内置 Icarus 14.0 development 的 `vvp.exe` 当前不可用；仿真脚本已切换到 `D:\Tools\iverilog-v12`，该问题不再阻塞当前 RTL 回归，但在升级工具前不得重新启用开发快照。
- 逻辑分析仪 8 路输入和 8 路回环激励输出已冻结为 J8 隔行相邻脚对 `3/4、7/8、11/12、15/16、19/20、23/24、27/28、31/32`，全部为 3.3 V；内部回环不能单独替代 Task 30 的物理闭环验收。
- CoreMark：官方 EEMBC checkout 已固定到 `1f483d5b8316753a742cbf5590caf5bd0a4e4777`，fixed/random 与 FPGA memory model 仿真均通过官方 CRC；实体板分数尚未采集，报告只能将当前值标为仿真估算。
- Git 仓库已建立，首次基线提交与 GitHub 私有远程状态见本次 Git 配置结果。

## 国赛冲刺基线

- 冲刺基准日：`D0 = 2026-08-29`；内部目标日：`D60 = 2026-10-28`。若官方截止更早，以官方截止为准。
- 本届唯一交付主线：Task 0～30、Task 32、33～35；Task 31 RLE 固定跳过。
- 硬节点：D3 硬件平台决策、D12 单周期候选 Reference、D20 `single_cycle_stable`、D35 Pipeline/GCC/性能计数器、D42 `pipeline_coremark_stable`、D52 逻辑分析仪 P0、D60 `competition_final`。
- 国赛证据链固定为：正确性（指令/Regression/提交级对比）、性能（CoreMark/MHz、Fmax、CoreMark/LUT、CPI）、应用（8 通道 Raw UART/SPI 闭环）、工程质量（Core/SoC 解耦、可复现构建、报告/视频/答辩）。
- 提前完成产生的时间只用于 Regression、Timing/CoreMark 复现、P0 稳定性和参赛材料，不恢复已冻结功能。

## 下一目标

**已完成（2026-09-17）**：调优后两套 CoreMark 位流与两套逻辑分析仪位流均已在实体板验证通过
（Score 29.559 @50 MHz / 47.295 @80 MHz PLL；两套 LA 各 80/80 J8 回环）。剩余动作是**把调优后位流提升为正式发布包**：
按 `scripts\export_final_submission.ps1` → `create_release_manifest.ps1` → `audit_release_package.ps1` 顺序执行（均需 pwsh 7）。

**次要（可选，独立一轮）**：数据事务握手流水化（`rtl/pipeline_cpu.v` 的 `dstate` REQ→RSP），
按实体板 CPI 归因（访存相关约占 4.5% stall + 主体事务等待）估计可降 CPI 约 0.4（约 −17%），
是 Score 第 (1) 项最显著的剩余空间；
必须独立一轮做 Before/After 并重跑 Task 23/24 全套 + 提交级 trace 对比 + 实体板 CoreMark。

主线目标：Task 33～35。自动化总回归、唯一最终配置发布包（位流/时序/约束/固件/上位机/实体证据一致）和候选材料已完成；实体 CoreMark 分数已补齐。下一步补齐 Task 29 Fabric Debugger 波形与三轮断电压力证据，随后更新报告/PPT/视频真实素材并再次运行完整回归、发布清单和包审计。

学习方式：先评审 `valid/ready` 请求/响应语义、地址/字节写使能和一次请求一次副作用，再由学习者实现最小范围的 Core 访存端口 RTL；Agent 负责 adapter/互连/外设侧 Testbench、随机背压和地址译码验证。任何新接口必须保持 Core 不含设备地址或专用端口。

并行的非 RTL 状态：D3 平台选择和管脚/电平归档已经完成，目标固定为 MES50HP；PDS、内部上电复位、BRAM 与实体 JTAG/LED 冒烟已作为 Task 10 证据归档。后续不得因板级冒烟通过而跳过 Task 11 的数据通路学习与单周期 CPU 验收。

## 更新规则

每完成一个任务，必须同步更新本文件：

1. 将通过验收的任务标记为 `[x]`，未通过的任务保持 `[ ]`。
2. 将“当前阶段”推进到下一个任务；不得跳过 `docs/roadmap.md` 的前置任务和 Gate。
3. 在“当前稳定 RTL”中列出已经通过相关 Regression 的稳定文件。
4. 在“当前 Regression”中记录测试名称和 `PASS` / `FAIL`；失败时不得标记任务完成。
5. 在“当前已知问题”中记录尚未解决的问题；重要 Bug 同时写入 `docs/debug_log.md`。
6. 将“下一目标”写成当前任务的具体验收目标。
7. 更新顶部日期，并确保记录与当前代码和实际测试结果一致。

---

## 2026-10-18 取指 FIFO 与返回地址栈 RAS（两项均已实现、均默认关闭）

两项都是"从开源项目借来的机制 + 完整 Before/After"，**结论都是净收益不成立**，
因此默认值均为关闭，交付位流与既有证据口径未变。逐条数据见 `docs/rtl_changes.md`。

### 1）取指预取队列（借鉴 lowRISC/ibex 的 prefetch buffer + fetch FIFO）

- 新增 `rtl/fetch_fifo.v` + `tb/tb_fetch_fifo.v`（27 条断言，深度 4/1 全 PASS）。
  集成路线为 `FETCH_FIFO_DEPTH` 参数（默认 1）＋ 24 个脚本补源文件。
- **实测收益：0 周期。** CoreMark RTL 仿真在深度 1/2/4、以及去掉 `!mem_block`
  门控的四种组合下，cycles **全部等于 1,251,724**。
- 原因：`coremark_imem` 的 `rsp_valid` **保持到被消费**，本身就等价于一个 1 深
  缓冲；`if_arm` 已消除取指气泡；单发射流水线的吞吐上限不在取指侧。
  FIFO 隐藏的是"延迟"，此处没有延迟可隐藏。
- 集成过程中修掉两个真 bug（都已留档）：
  ① `DEPTH=1` 时指针越界读 `ent_*[1]` 得到 X，顺着 `ifid_inst` 污染流水线；
  ② 队列内部用自己算的 `in_ready` 判定"接收"，与外部 `i_rsp_ready` 的
     `!mem_block`/`if_rsp` 门控不一致，导致**同一条指令被提交两次**
     （M 扩展回归 0x78 的 `sw`）。修法：新增 `in_fire`，由真实握手驱动。

### 2）返回地址栈 RAS（`ENABLE_RAS`，默认 0）

- 新增 `rtl/ras.v` + `tb/tb_ras.v`（27 条断言，深度 8/4/2/1 全 PASS）、
  `scripts/run_ras_tb.ps1`；`rtl/pipeline_cpu.v` 加 `ENABLE_RAS`/`RAS_DEPTH`、
  `btb_is_ret[15:0]` 位图与 `predictor_target_eff`；独立工程 `fpga/coremark_ras_85m/`。
- **rv32i**：仿真 cycles 1,251,724 → 1,226,872（**−1.99%**）
- **rv32im**：仿真 604,288 → 603,090（−0.20%）；**实体板 ticks
  1,759,901,953 → 1,755,563,957（−0.25%）、Score 193.192 → 193.669**
  （四 CRC 全过、`-march=rv32im`、20.653 s）——仿真与实体板互相印证。
- **但面积 +110 LUT（4198 → 4308，+2.62%）大于分数收益（+0.25%）**，
  故 **CoreMark/LUT 0.04602 → 0.04496（−2.30%）**；WNS +0.250 → +0.117 ns。
  深度扫描 4/8/16 周期数完全相同，减小深度也省不下足够 LUT。
- rv32i 的 −2% 与 rv32im 的 −0.25% 差异原因：rv32i 下每次乘法都调 `__mulsi3`
  （84.3% 提交落在其中），call/ret 对极多；rv32im 后这些调用整体消失。
  **引用 RAS 收益必须写明 ISA。**

### 当前状态

- `ALL AUTOMATED FINAL REGRESSION PASS`（RAS 默认 0 与默认 1 两种配置均实测 PASS）。
- 板子已恢复为交付位流 `la85`。
- 交付物、位流哈希、`claims_map` **均未改动**。
- **下一目标**：面积敏感项优先。任何"加分"必须同时给 `ΔScore/ΔLUT`，
  判据是 `ΔScore/ΔArea > 1`，否则 CoreMark/LUT 一定倒退。

---

## 2026-10-18 编译优化等级：`-O2` → `-O3 -funroll-all-loops -finline-functions`

### 结论：三项指标全部正向，零面积、零时序风险，已在实体板验证

| 指标 | `-O2`（交付基线） | **`-O3 -funroll-all-loops -finline-functions`** | 变化 |
|---|---:|---:|---:|
| Score @85 MHz | 193.192 | **201.457** | **+4.28%** |
| CoreMark/MHz | 2.272 | **2.370** | **+4.31%** |
| ticks | 1,759,901,953 | **1,687,704,396** | −4.10% |
| 运行秒数 | 20.704 s | **19.855 s**（≥10 s ✓） | — |
| LUT | 4198 | **4185** | −0.31% |
| 路由后 WNS | +0.250 ns | **+0.341 ns** | 余量变大 |
| **CoreMark/LUT** | 0.046020 | **0.048138** | **+4.60%** |

判据 `ΔScore/ΔLUT = 4.28 / (−0.31)` → 远超 1，**这是至今唯一"三项全赚"的改动**。
证据：`release/evidence/coremark_uart_opt85_20261018.log`、
`coremark_board_opt85_20261018.json`、工程 `fpga/coremark_opt_85m/`
（两次独立采集 ticks 完全一致，确定性可复现）。
板上自证行：`Compiler flags : -O3 -funroll-all-loops -finline-functions -march=rv32im -mabi=ilp32`。

### 改动内容（全部可开关，默认值仍是 `-O2`）

| 文件 | 改动 |
|---|---|
| `software/coremark/Makefile` | 新增 `COREMARK_OPT ?= -O2` 与 `COREMARK_OPT_ESC`（转义空格，使优化选项作为**一个** argv 传给 gcc）；`CFLAGS` 改用 `$(COREMARK_OPT)` |
| `software/coremark/core_portme.h` | `COMPILER_FLAGS` 由写死 `"-O2"` 改为 `COREMARK_OPT_STR`（未定义时退回 `"-O2"`） |
| `scripts/generate_coremark_fpga_memory.ps1` | 新增 `-Opt` 参数并透传 `COREMARK_OPT` |
| `scripts/run_coremark_pipeline_tb.ps1` | 新增 `$env:COREMARK_OPT` 开关 |
| `fpga/coremark_opt_85m/` | **新增独立工程**（镜像由 `-Opt` 生成），不覆盖交付工程 |

### 修掉的诚信问题（重要）

`core_portme.h` 里 `COMPILER_FLAGS` 原本**写死** `"-O2 -march=…"`。
用别的优化等级构建时串口自证行会**说谎**（实测第一次 `-O3` 运行仍打印 `-O2`）。
现在由 Makefile 传入实际选项，已复测确认自证行正确。
**以后任何改编译选项的动作，都必须先确认这一行跟着变。**

### 待决事项（未擅自改动交付口径）

1. `-O2` 与 `-O3` 是**两个口径**。是否把 `-O3` 升为交付口径由用户决定；
   若采用，`docs/competition_scoring.md` §2 的三项实测值、`claims_map`、
   交付包都要同步重出，并保留 `-O2` 作为历史对照点。
2. **未解释的复现偏差（会话开始前已存在）**：用当前源码树重建的 `-O2` 镜像与
   10/14 交付的 `fpga/coremark_im_85m/rtl/coremark_imem.mem` **不逐字节一致**
   （3045/8192 行不同）。该位流 mtime 为 2026-10-14，且会话开始时 `git status`
   已显示 `M software/coremark/Makefile`、`M software/coremark/core_portme.h`，
   说明交付镜像并非由当前源码树产生。**提交前必须查清**。本轮只如实记录，未擅自"修好"。

---

## 2026-10-19 乘法并行部分积：`MUL_LAT` 3 → 2（**已成为默认配置**）

> 完整记录见 **`docs/mdu_parallel_partial_product.md`**（算法、三方对照、关键路径、复现命令）。
> 起因：`docs/coremark_cpi_analysis.md` §8.4 的优先级里，`MDU 去阻塞 ≈4.5%` 是除"数据口"之外
> 唯一不需要碰取指/预测/提交时序的项。

### 改了什么

`rtl/mdu.v` 的乘法从"两级**串联** 16x32 部分积"改成"四路**并联** 16x16 部分积 + 窄位宽（17/33 位）
加法树 + 推测进位选择"，乘法占用 ID/EX 的拍数由 3 降到 2；除法通路一行未改。
新增参数 `MUL_LAT`（3/2/1，**默认 2**）与 `pipeline_cpu` 的 `MDU_MUL_LAT` 透传，
旧实现在 `MUL_LAT=3` 分支里**完整保留**，可逐拍对照。

### Before / After（实测）

| 项 | MUL_LAT=3（旧） | **MUL_LAT=2（新默认）** | 变化 |
|---|---:|---:|---:|
| RTL 仿真 cycles（rv32im 一次迭代） | 604,288 | **594,792** | **−1.571%** |
| RTL 仿真 `mdu_block` | 24,307 | **14,810** | −9,497（= 每迭代乘法条数） |
| RTL 仿真 CoreMark/MHz | 1.965 | **2.002** | **+1.88%** |
| RTL 仿真 cycles（**rv32i**） | 1,251,724 | **1,251,724** | **0（逐位相同）** |
| RTL 仿真 `instret`（rv32im） | 0x51327 | **0x51327** | **不变** |
| 官方 CRC 四行 | 全过 | **全过** | 不变 |
| LUT / FF（85 MHz PnR） | 4185 / 3361 | **4139 / 3324** | **−46 / −37** |
| 路由后 WNS（85 MHz） | +0.281 ns | **+0.115 ns** | −0.166 ns，仍 `All Constraints Met` |
| 估算 Fmax | 87.0800 MHz | **85.8391 MHz** | — |
| **板级 ticks（4000 迭代）** | 1,759,901,953 | **1,722,317,953** | **−2.135%** |
| **板级 Score** | 193.192 | **197.408** | **+2.183%** |
| **板级 CoreMark/MHz** | 2.272 | **2.322** | **+2.20%** |
| 板级耗时 / `crcfinal` | 20.704 s / `0x65c5` | **20.262 s / `0x65c5`** | CRC 相同 |

- **rv32i 逐位不变**（`mdu_block=0`，rv32i 根本没有硬件乘法）⇒ 这条路径只影响 MUL 指令。
- 收益归因严格对账：`mdu_block` 三档 24,307 / 14,810 / 5,313，相邻差都恰好是 **9,497**（每迭代乘法条数），
  剩余 5,313 拍是除法（三档相同）。
- `ΔScore/ΔArea`：分数 +1.88%、面积 −1.10%，**同向为正**（继 `-O3` 之后第二个）。
- **仿真与实板逐拍吻合**：仿真 CoreMark 窗口 ticks 差 **9,396 拍/迭代**；
  实板 (1,759,901,953 − 1,722,317,953) ÷ 4000 = **9,396 拍/迭代**，两者完全相同。
- **基线位流复现归档值**：`ticks = 1,759,901,953` 与 2026-10-14 归档 `cmim85` **逐位相同**。

### 被实测否决的 `MUL_LAT=1`

全组合乘法（挡 0 拍）在 85 MHz **违例 WNS −4.471 ns / 估算 61.59 MHz**：
关键路径 `core/rf/regs → 前递 MUX → 一级 APM` 就已 12.189 ns，超过 11.7647 ns 周期。
⇒ 85 MHz 下不存在"乘法输入直连前递操作数"的结构，`M_IDLE` 那一拍是必需的。
保留为对照工程与证据，不进入任何配置。

### 回归（全在新默认 MUL_LAT=2 下跑，24 项全 PASS）

RV32I 全量、流水线 13 项、GCC 单周期/流水等价、Trap 契约 99 断言、Trap 黄金判据、
单周期 Reference、MDU 单元（46 项 × 3 档）、M 扩展流水线 vs Reference、性能计数器、
性能 MMIO、定时器中断、CSR、FPGA dmem、MES50HP 流水 SoC、CoreMark rv32i(固定/随机背压)、
CoreMark rv32im、CoreMark FPGA 存储器模型（官方 CRC）、逻辑分析仪 SoC / 板级顶层 /
PLL80 顶层 / 采集引擎 / MMIO / 应用 MUX。

### 未做 / 风险（**必须如实带入材料**）

1. **已在实体板验证**（2026-10-19，MES50HP/COM11）：两颗位流分别上板跑官方 CoreMark 4000 迭代，
   Score 193.192 → **197.408**、ticks −2.135%、`crcfinal 0x65c5` 两次相同、`flush_count` 两次逐位相同。
   上板完成后板子**已恢复为交付位流 `la85`**（`C017ED10…`）。
2. **交付逻辑分析仪位流（la85）未重打**：`release/` 内既有位流与全部哈希一个字节未动。
   若要把这次收益并入交付配置，需重打 la85 + 重跑 100/100 板级验收 + 同步 `claims_map` 的 4 处哈希。
3. **CPI 不得引用**：这两次采集用的是默认 `PERF_WINDOW_ALIGN=0` 镜像，性能计数器自由运行，
   PERF 行的 `cycle/instret/stall/branch` 与 JSON 的 `cpi_x1000` 含启动与等待 `R` 的轮询，两次不可比。
   可引用只有 `ticks/Score/CoreMark/MHz/CRC/flush`。要做 CPI 归因必须换 `PERF_WINDOW_ALIGN=1` 镜像。
4. **归档工程用当前源码树重建会失败**：`fpga/coremark_im_85m` 等 09-30/10-14 的配方缺 `rtl/ras.v`，
   直接 `pds_shell` 会报 `Verilog-4072: 'ras' is referenced to undefined module`。
   本次三个对照工程已在配方里补上；归档工程按纪律保持不动（位流哈希是交付证据）。
5. 因上一项，**基线数字只能引用同配方重建的 `fpga/coremark_mul3_85m`**，
   不得引用归档 `coremark_im_85m` 的 4198 LUT / +0.250 ns（那是另一套源文件集）。
6. WNS 余量由 +0.281 ns 降到 **+0.115 ns**（仍 `All Constraints Met`）；板级已实测跑通，
   但余量变小这件事必须在材料里写明。

### 下一目标

①**可选**：若要把这次收益并入交付配置，重打 la85 位流 + 重跑 100/100 板级验收 + 同步
`claims_map` 4 处哈希（本次**未做**，交付位流与哈希保持原样）；
②按 `docs/coremark_cpi_analysis.md` §8.4 的顺序继续：store 提前退休（≈3.2%）→ 非阻塞 load（≈12.2%，风险最高）；
③若要给 CPI 做归因，必须先换 `PERF_WINDOW_ALIGN=1` 的镜像重采，否则只能引用 ticks/Score。

---

## 2026-10-21 提交级 trace 可视化（**全链路已闭环，含实板**；用户当日批准的范围变更）

> **状态：RTL / 固件 / 上位机 / PDS 位流 / SoC 端到端仿真 / 实板两枪 全部 PASS。**
> 实板证据在 `release/evidence/trace85_board/`（README 里有逐条数字），
> 位流 `945F36E497740628A635E295F6132E86D88D5FEA2C25CA2C43C221A9664F290D`
> （`All Constraints Met`，85.000 MHz）。
> **交付位流 `la85`、100/100 板级验收证据、`claims_map` 四份哈希一个字节未动**；
> 本能力是附加演示位流，不改交付配置。

### 0. 范围与授权（用户 2026-10-21 明确选择）

- 方案：**A 全量** —— Core 提交级 trace 缓冲 + 逐指令依赖图 / 寄存器热力图 /
  总线泳道 / 字符↔指令联动 / 反汇编映射 / 时间轴回放。
- 交付形态：**独立新位流 `fpga/trace85`**。`la85` 位流、100/100 板级验收证据与
  `claims_map` 四份哈希**一个字节不动**。
- 同时批准：①范围变更写入本文档与 `docs/application_logic_analyzer.md`；
  ②由 Agent 代写这部分 Core 外部 RTL。

### 1. 为什么做这个（用户原话与事实校准）

用户判断："再怎么提升 CPU 性能对逻辑分析仪的工程展示效果也没大影响，人眼也区分不出来"。
**结论采纳、理由纠正**：CoreMark/MHz、Fmax、CoreMark/LUT 是官方三项明确指标，
评委看数字不看眼睛；停手的正确理由是"剩余空间只剩非阻塞 load（≈12.2%）且风险最高，
D-7 不值得拿已跑通的交付位流去赌"。

用户要的"实时展示数据流"**物理上不可能逐条实时**：一条提交记录最紧 132 位 ≈ 16 字节，
85 MHz / IPC≈0.6 下内核产出 ≈600 MB/s，而 115200 8N1 只有 11.52 kB/s —— 差约 5 万倍。
因此口径按真实仪器来：**触发采集一窗 → 上传 → 回放**，"实时"这个词不进材料。

同时纠正了三处工程事实：

1. `trace_*` 11 个字段**早就是 `pipeline_cpu` 的冻结对外端口**（`docs/interfaces.md` §6.1），
   而板级顶层把它们全部悬空（`.trace_pc()` …），综合直接优化掉 —— **数据线一直在，我们只是没接**。
2. 原来的"镜像模式"**并没有让 CPU 处理字符串**：`uart_getc()` 只用来收上位机的命令包，
   `HELLO,RISC-V` 是被板级 `assign loopback_tx={uart0_rx,...}` 物理环回给分析仪抓的。
   所以"CPU 处理字符串"这件事本身也要新写固件。
3. 115200 下一个字符 86.8 µs ≈ 7378 拍，其中 99% 是轮询串口状态位 —— 这正好是
   "用自研仪器量自研 CPU 在忙什么"的第一个硬数字。

### 2. 新增文件与改动（Core 一行未改）

| 层 | 文件 | 内容 |
|---|---|---|
| RTL 新增 | `rtl/trace_buffer.v` | Core 外部提交级 trace 缓冲：4096×132 位记录 + 256×24 打点表；arm/stop/clear/mark；`full` 区分"写满收尾"与"软件 stop" |
| RTL 新增 | `rtl/core_trace_mmio.v` | 该缓冲的 MMIO 从端口（窗口内 offset 0x00…0x30，共 13 个有效寄存器） |
| RTL 新增 | `rtl/application_mmio_mux3.v` | APP 窗口三目标汇合：0x0 性能计数器 / 0x1 逻辑分析仪 / **0x2 trace**；既有 `application_mmio_mux.v` 原样复用、一字未改 |
| RTL 新增 | `fpga/trace85/rtl/mes50hp_trace_top.v`、`mes50hp_trace_pll_top.v` | 新 SoC 顶层与 85 MHz PLL 顶层；与 la85 的差别只有 3 处（mux3 / trace_* 接线 / 多一个实例） |
| RTL | 无 | `rtl/pipeline_cpu.v`、所有既有外设与 `application_mmio_mux.v` **均未修改** |
| 固件 | `software/logic_analyzer/logic_analyzer.c` | 新增 **0xAA** 4 字节命令（字符数 + 阶段 + XOR）与 `trace_and_report()`；两个阶段：0=只记处理过程，1=连串口轮询一起记；靠 `TR_MWR` 打点把字符锚到记录位置 |
| 上位机 新增 | `python/trace_view.py` | 记录位段唯一拆解表、RV32I(+M) 反汇编、数据流依赖边、自动判据、单页生成 |
| 上位机 新增 | `python/trace_viewer.html` | 单页可视化（模板占位 `__TRACE_DATA__`，与 `waveform_viewer.html` 同一套路，不引框架） |
| 上位机 新增 | `python/trace_board.py` | 板级抓取（0xAA 帧、等 `TRACE_ARMED` 再发字符串）、落盘 log/json/html |
| 测试 新增 | `tb/tb_trace_buffer.v`、`tb/tb_core_trace_mmio.v`、`tb/tb_core_trace_soc.v`、`python/tests/test_trace_view.py` | 见下 |
| 脚本 新增 | `scripts/run_trace_buffer_tb.ps1`、`run_core_trace_mmio_tb.ps1`、`run_core_trace_soc_tb.ps1`、`run_trace85_pds.ps1` | 均支持 `-OutDir`（受限环境下可把产物指到别处） |
| 脚本 改 | `scripts/program_board.ps1` | 新增 `-Config tr85` 一项，指向 `fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit` |
| 工程 新增 | `fpga/trace85/` | PDS 工程（recipe 里显式补 `fetch_fifo.v` / `ras.v`，归档 la85 配方缺它们会直接报未定义模块） |

### 3. 已通过的验证

| 验证 | 命令 | 结果 |
|---|---|---|
| trace 缓冲单元测试 | `scripts\run_trace_buffer_tb.ps1` | **`ALL TRACE BUFFER TEST PASS`**（10 项：复位/arm/逐字段对拍/idle 不记录/打点/stop/写满/溢出/clear/重新 arm） |
| trace MMIO + mux3 测试 | `scripts\run_core_trace_mmio_tb.ps1` | **`ALL CORE TRACE MMIO TEST PASS`**（11 项，含零 strobe 无副作用、越界报错、**既有 perf/la 子窗口逐字未变**） |
| 上位机单测 | `python -m unittest python.tests.test_trace_view` | **30 项 OK**（位段/反汇编/镜像解析/回包解析/判据/依赖边/页面生成/页面 JS 用 `node --check` 解析/JS 引用的 DOM id 全存在/地址不一致必须 FAIL） |
| 固件编译（两种配置） | `make -C software/logic_analyzer all`（AUTOSTART=0/1） | 均 PASS，`COREMARK ISA CHECK PASS: RV32I-only ELF` |
| 端到端仿真（两场景） | `scripts\run_core_trace_soc_tb.ps1` | **`ALL CORE TRACE SOC TEST PASS`**：场景 1 `declared=100 lines=100`、`ascii=HELLO,RV`、`status=0x04`；场景 2 `declared=859 lines=859`、`ascii=ABC`、`status=0x04`；UART 零帧错误 |
| **实板 阶段 0** | `program_board.ps1 -Config tr85` → `python python\trace_board.py --port COM11 --phase 0 --text "hello,rv"` | **`TRACE BOARD PASS`，15/15 条判据**：100 条提交 / 8 打点 / 19 个 PC / `status=0x4`；**每字符 12 条提交**，marks 间隔 `[12,12,12,12,12,9,12]`；`pc 与位流镜像同源` 与 `store 有效地址与记录低 12 位一致` 均不一致 **0 条**；17 次写存储里 **8 次命中 MMIO**（全是打点寄存器 `0x1000222C`）、9 次写数据 RAM |
| **实板 阶段 1** | 同上 `--phase 1 --text "ABC"` | **`TRACE BOARD PASS`，14/14 条判据**：4096 条（窗口写满）/ 3 打点 / 22 个 PC / `status=0xC`（溢出**合法**，`count==容量`）；**前 4 个热点占整窗 99.49%**，其中三条就是 UART 忙等循环（各 1358/1358/1357 次）；`pc 与位流镜像同源` 在 4096 条上不一致 **0 条** |
| PDS 综合/布局布线 | `scripts\run_trace85_pds.ps1` | **`All Constraints Met`**；位流 `945F36E497740628A635E295F6132E86D88D5FEA2C25CA2C43C221A9664F290D` |
| **全量回归** | `scripts\run_final_regression.ps1`（不带 `-RunPds`） | **`ALL AUTOMATED FINAL REGRESSION PASS`，退出码 0**；三条 trace 用例已并入；交付位流 `la85` 哈希复算仍为 `C017ED10195502739BEBF914DD3BC6F3CAA84C0EAEB6E9E97559248B003FAA4F`（**未变**） |
| 冻结范围审计 | `scripts\run_scope_audit.ps1` | **`SCOPE AUDIT PASS`**（扫描根已加入 `fpga/trace85`，75 → 81 文件） |
| 资源 | 同上（`pds_trace85_build.log`） | LUT **3810+2144**（两 bank，15% / 13%）、APM 4、**DRM 40 / 134（30%）**、`LUT as Distributed RAM = 0` |

PLL 输出经时序报告确认：`clk_50m|u_pll/u_pll_85m/CLKOUT0_Inferred` 周期 **11.7647 ns = 85.000 MHz**。

实板两枪的**仿真↔实板一致**：阶段 0 的 8 个打点索引在仿真与实板上都是
`[7,19,31,43,55,67,76,88]`（同一份固件、同样的每字符 12 条提交）。

阶段 0 的热点就是逐字符处理循环，每个字符各命中一次：

| PC | 条数 | 指令 |
|---|---:|---|
| `0x9BC` | 8 | `addi x14,x8,0` |
| `0x9C0` | 8 | `lbu x15,0(x8)` |
| `0x9C4` | 8 | `sw x15,0(x12)` |
| `0x9C8` | 8 | `addi x13,x15,-97` |

### 4. 本轮定位到的三个真 bug（都已修）
1. **假 overflow（RTL）**：`overflow` 原来按 `done && trace_valid` 置起，而软件 `stop` 之后
   CPU 当然还会继续退休指令 ⇒ 每一次正常收尾都报溢出（实测 `status=0x0C`）。
   改为只用 `full`（写满收尾）才允许置 overflow。判据补了 `depth` 参数：
   `overflow==0 or count>=depth`。
2. **上位机时序纪律（TB/上位机）**：0xAA 命令必须在固件回到命令循环（打印 `LA_READY`）
   之后再发。UART RX **没有接收 FIFO**，在固件阻塞发 `LA_READY` 期间发命令会被后续字节覆盖，
   固件再也收不到命令，仿真白等 300 万拍。已在 TB 里加 `wait_mark(M_READY)` 并写进注释。

另外修掉一个**记录读出截断**隐患：132 位装不进 4 个 32 位字，第一版 `RD_W3` 写成
`{28'b0, rd_record[131:96]}` 会静默丢掉第 128…131 位（error 位与 mem_data 最高 4 位），
现改为 5 个字读全（`0x30 = RD_W4`）。

### 4.1 界面：一个窗口两页 + 输入框（2026-10-22，用户当场追加）

用户先问"是不是只能固定展示某些字符"，随后明确要求：
**"一个 UI 界面分成两页，第一页正常的逻辑分析仪界面，第二页就是热力图实时显示 CPU 分析过程"**。

| 层 | 文件 | 内容 |
|---|---|---|
| pyUI | `python/mes50hp_validation_ui.py` | 改成 `ttk.Notebook` 两页：**① 逻辑分析仪（八通道波形）** = 原来整套控件一行未改；**② CPU 数据流（寄存器热力图）** = 输入框 + 阶段 + 采集按钮 + **Tk Canvas 现画的热力图/泳道** + 逐条指令表 + 依赖详情 + 播放拖动 + 判据日志 |
| 同源 | `python/trace_view.py` | `expected_phase0()` —— 固件那段处理逻辑（大写化 + XOR）的**唯一**实现；界面预演与自动判据都调它 |
| 实时 | 同上 | 「连续采集（实时刷新）」：上一枪跑完立刻再采并重画 |
| 启动 | `main()` 新增 `--page 2 --capture-text "abc"` | 打开就停在第 2 页并自动采一枪（不带参数时行为与以前完全一样） |
| 一键 | `python/capture_trace.cmd` | 改成**问你要发什么**（也可 `capture_trace.cmd "abc"`） |
| 测试 | `python/test_trace_ui.py`（15 项）、`scripts/run_trace_python.ps1` | 两页真的存在且标题对得上、第 2 页控件**真的住在第 2 页**、第 1 页原控件没被搬走、超长/非 ASCII/空串在点按钮前被拦、预演与判据同源 |
| 板级 | `python/trace_ui_board_check.py` | **真走界面路径**（真构造 pyUI、真填输入框、真点按钮），并断言**界面里真的画出了热力图**（`trace_canvas.find_all()` 非空） |
| 打包 | `scripts/export_final_submission.ps1` | `trace_view.py`/`trace_board.py`/`trace_viewer.html`/`capture_trace.cmd` 一并进包 |

**实板验证（真界面路径）**：
`python python\trace_ui_board_check.py --port COM11 --text "hello,rv" --text "abc!XYZ 123"`
→ `TRACE UI BOARD CHECK PASS`，两串都是 `nodes=100/115、heat_items=94/107、lane_items=20/26`。
即"任意字符串 + 界面内热力图"这条在板上成立。

**本轮踩到并修掉的两个界面坑**（都不是 RTL）：
1. **Notebook 子页不能再 `pack()`**：把 page1 pack 一次会把标签页体系挤掉，
   表现为 `notebook.tabs()` 只剩 1 个（测试直接抓到了）。
2. **`ttk.Scale.set()` 会触发自己的 `command`**：`set → command → _trace_select → set …`
   无限递归，窗口一打开就 `RecursionError` 崩掉。加 `_scrub_syncing` 标志后正常。

**仍然成立的两条边界**（已在 §6.11.9 写明）：字符数与 ASCII 限制按阶段不同
（0/1 档 ≤32、2 档 ≤16）；能选的被测程序只有固件里烧进去那三档，加第四档要改固件重打位流。

### 4.2 热力图"太贫瘠"：加维度 + 加一档被测程序（2026-10-22 用户反馈后）

> 本节记录的"四块画布"版面已在 2026-10-24 合并成**一条时间轴**（见 §4.3）；
> 这里保留当时的量化过程与"加维度"的结论，数字都是那一版实测值。

用户反馈："现在的热力图有点太贫瘠了，没啥数据。"先量化，再动手：

| | 记录 | 有写回 | 用到的寄存器行 | **填充率** | 读寄存器次数（**原来没画**） |
|---|---|---|---|---|---|
| 阶段 0（旧） | 100 | 59 | **8/32** | **1.8%** | 130 |
| 阶段 1（旧） | 4096 | 2732 | 6/32 | 2.1% | 4093 |

**结论：这是结构性稀疏**——一条指令最多写一个寄存器，填充率天花板 = 写回占比 ÷ 32 行 ≈ 2%。
所以只能"加维度"或"换被测程序"，美化没用。两件事都做了。

**A. 加维度（纯界面，未动 RTL 与位流）**

| 加了什么 | 效果 |
|---|---|
| **把"读"画上**（细横条） | 阶段 0 的绘制元素 59 → 189（+220%）；壳级 `heat_items` 94 → 224 |
| **填充色改成"值从哪来"** | 青=load 读进来的、绿=ALU 算的、紫=立即数、黄=PC；一眼看出数据来源，不再只是"哪个寄存器被写了" |
| **PC 热力图** | 纵轴=本窗口出现过的 PC，循环变成整齐的阶梯条纹——**这块最像"看得见的数据流"** |
| **地址热力图** | 纵轴=写存储地址字序号低 5 位；缓冲与 MMIO（打点寄存器）用不同颜色分开 |
| 依赖边连线 | 选中指令的每个来源画一条折线到它自己，跨列时能看出跨度 |
| 鼠标悬停 | 不点也能看到那一列的指令与动作 |

**B. 试过再加一档被测程序（冒泡排序）—— 放不下，已撤回**

思路是加一档"读-改-写成对出现"的负载让依赖链变密。写完、上板确实跑通了：
16 字符 → **980 条提交、29 个 PC、比较 120 次 = n(n-1)/2**，判据 15/15 PASS。

**但它把镜像模式测坏了**，暴露出一条一直存在的隐患：

- DMEM 只有 4 KB，栈顶固定在 `0x1000`（`start.S` 的 `lui sp,1`）；
- 加排序后 `.bss` 结束在 `0x0FD4` → **栈余量只剩 44 字节**；
- 镜像路径实测需要约 **224 字节**栈帧（`-fstack-usage` 量出：`main` 112 +
  `capture_and_report` 80 + `uart_hex` 32）→ 栈压进 `.bss` 踩坏 `dec[]`，
  `run_logic_analyzer_mirror_tb` 由 **PASS 变 2 条 FAIL**
  （`LA TEXT hex=` 里出现空格、`bytes=0000000` 被截断）。

结论：**这个交互固件已经顶到 4 KB DMEM 的天花板**。再加功能必须扩 DMEM，
而要动 `start.S` 的 sp、`logic_analyzer_program_memory.v` 的 DEPTH、
`soc_data_interconnect` 的 `RAM_LAST_ADDR` 以及 4 个板级项目与其 TB ——
那会作废已冻结的 `la85`/`la50` 位流与 100/100 证据，本轮**不做**。

处置：**撤回排序档**，固件恢复到 `used_words=922`，
`run_logic_analyzer_mirror_tb` 重新 `ALL LOGIC ANALYZER MIRROR TEST PASS`；
`trace85` 位流随之重打（`All Constraints Met`），最终哈希
`945F36E497740628A635E295F6132E86D88D5FEA2C25CA2C43C221A9664F290D`。

**教训（值得写进答辩）**：加高日志区会把日志顶出屏幕（窗口本来贴着屏幕底边），
所以这一轮把四块画布高度压到 150/70/70/38、把播放条从"叠在泳道上"移进布局，
最大化窗口下实测余量 15 px。

**一个必须如实说的限度**：换程序能让 x 轴和依赖链填满，但**32 行寄存器永远填不满**——
一个紧凑裸机程序不会用到 32 个寄存器。所以"密度"靠的是加维度，不是指望行填满。

### 4.3 第 2 页重排：一块画布、一根轴、一根光标（2026-10-24，用户反馈"太乱"后）

用户的评语是"第二页太乱了，你可以在网上找找可以借鉴的"。查了三个成熟工具，它们指向同一个范式
（Perfetto 的 track 视图 / GTKWave·Surfer 的波形栏 / Ripes 的架构状态视图）：
**多条泳道共享一根时间轴、一个光标、左侧名称栏、详情另开一栏**。
上一版（四块各自独立的 Canvas、四套刻度、四套标签）恰好把这三条全反着做了。

| 改了什么 | 为什么 |
|---|---|
| 四块画布 → **一块**画布，四组泳道（寄存器 / PC / 写存储地址 / 事件）上下叠、共用顶部标尺 | 一套刻度才能横向对齐；上一版四块各画各的，"对不齐"就是"乱"的主因 |
| 一条黄色虚线光标贯穿全部泳道；选中指令在每组泳道里用**空心**黄框标出自己那一行 | 光标是唯一的"当前时间点"；填色高亮会盖住那一行真正的数据块 |
| 所有泳道共用同一个行距（下限 7 px、上限 20 px，行数放不下就按热度砍行） | 上一版 PC 泳道 21 行 × 5 px，7 pt 的字直接重叠成糊 |
| 一条记录**至少 3 px**，超出部分滚动显示；多画一条全览条（整窗密度 + 黄框标出视窗段） | 4096 条压进 1160 px = 一列叠 3～4 条，颜色只能"谁最后写谁说了算"，整块糊成色带（实测截图如此） |
| 指令表挪到左侧、当前行**整行铺底色**；详情/判据收进底部标签页 | 上一版 4 块画布把高度吃光，指令表/详情被挤到屏幕外 |
| 静态层与光标层分开重画（`tl_cur` 标签） | 4096 条的窗口播放时不能每次都重建全部图元 |

**验证（2026-10-24 实板，板子重新下载同一位流 `945F36E4…`）**

| 项 | 命令 | 结果 |
|---|---|---|
| pyUI 单测 | `python -m unittest test_trace_ui` | **25 项 OK** |
| 上位机判据 | `python -m unittest tests.test_trace_view` | **30 项 OK** |
| 真界面路径（阶段 0） | `python python\trace_ui_board_check.py --port COM11 --text hello,rv --phase 0` | `TRACE UI OK nodes=100 可见=100 条 items=411 rows={reg:9,pc:12,mem:8}` → `TRACE UI BOARD CHECK PASS` |
| 真界面路径（阶段 1） | `... --text ABC --phase 1` | `nodes=4096 可见=308 条 items=1817 rows={reg:6,pc:12,mem:4}` → PASS |
| 四条 trace 回归 | `run_trace_buffer_tb` / `run_core_trace_mmio_tb` / `run_trace_python` / `run_core_trace_soc_tb` | 全 PASS（本轮只改上位机，RTL 未动） |

本轮踩到并修掉的两个坑（都不是 RTL，详见 `docs/debug_log.md`）：

1. **`tk.Text` 的标签名 `sel` 是保留名**（由 `-selectbackground` 接管），
   外面 `tag_configure("sel", background=...)` 会被**静默忽略**：`tag_names()` 里有、
   `tag_cget()` 也读得回颜色，界面上却一点底色都没有。高亮标签改名 `cur` 后立刻正常
   （是 4 倍放大截图才发现"根本没画出来"的）。
2. **自动化检查会被模态弹窗挂死**：采集失败时 `_poll_events` 弹 `messagebox.showerror`，
   `app.update()` 永不返回，检查挂十几分钟；再叠上 `python` 的 stdout 被缓冲，
   一个字的日志都看不到。现在检查脚本把弹窗换成"记账"，失败立即打印原因。
3. **指令表被插入点横向顶走**：`tk.Text` 插入后插入点被顶到行尾，Tk 为了让它可见把画面
   横向滚了几像素，行首的 `>` 与高亮列被切掉。**离线灌数据截图没触发、真采一枪才暴露**，
   现已 `mark_set("insert","1.0") + xview_moveto(0)` 并加单测钉死。
4. `scripts/run_final_regression.ps1` 末尾补 `exit 0`：全部 64 项 PASS 时
   `$LASTEXITCODE` 仍会残留成"某条容忍过 stderr 的原生命令"的返回值（实测带 exit 1 出来），
   外部 CI / 交接脚本会误判成失败。失败路径仍由 `throw` + `exit 1` 负责。

另：这次失败的根因是**板子断电后丢了 SRAM 位流**（`TimeoutError: bytes=0`，等不到 `TRACE_ARMED`），
重新 `scripts\program_board.ps1 -Config tr85` 后两条界面路径都通过。

**必须如实说的限度**：一条记录 3 px 意味着 4096 条要看约 11 屏，**不是"一眼看全"**。
本页从不假装能一次看全 4096 条——要么看全览条的密度，要么看某一段的逐条细节。

### 4.4 波形 + 指令流**按拍对齐**（2026-10-24，用户"按你的来，继续干"之后）

这是"让评委眼前一亮"那条路的第三步（前两步是本次会话的评估与重排）：
把 8 通道 Core 探针波形和提交级 trace 放进**同一次运行**，并用一条独立的物理信号证明对齐。

| 层 | 改了什么 |
|---|---|
| 固件 | 新增 `0xAB` 组合命令（4 字节）：先 arm trace → 再 arm LA（Core 探针源、`div=0`、触发=退休上升沿）→ 跑负载 → 等 LA 采满 → 最后 stop trace；回包内含波形块 + 指令流块 |
| 镜像 | tr85 固件扩到 **8 KB**（`-DRAM_KB=8` + `link8k.ld`，栈顶 0x2000、DEPTH 2048、`RAM_LAST_ADDR 0x1FFF`）；**la85/la50 仍是 4 KB 且逐字节不变**（生成器默认档不传任何容量变量） |
| 生成器 | `generate_logic_analyzer_fpga_memory.ps1` 新增 `-RamKb`，并按 `log2(DEPTH)+1` 生成索引位宽（1024→`[11:2]`、2048→`[12:2]`）；对默认档是空操作 |
| 位流 | tr85 重打：`All Constraints Met`，WNS +361 ps / WHS +186 ps，DRM 44/134（原 38/134）；新哈希 `2148CD6F009FCED49D65800B76E4BBB33627C9872186A8E4892776F80A62B5F5` |
| 上位机 | `trace_board.run_wave/build_wave_packet/parse_wave_response/capture_wave`；`trace_view.wave_lanes/align_wave/judge_wave`（位序与判据的唯一实现）；第 2 页新增「波形+指令」按钮与窗口档 |
| 界面 | 载入波形后时间轴横轴**从"记录号"变成"拍号"**：最上面多一组 **Core 探针（每拍）** 泳道，下面每条记录按它退休的那一拍定位、按"退休到下一条退休"的跨度画宽（多拍指令自然变宽） |
| 仿真 | `tb/tb_core_trace_soc.v` 新增**场景 3**（0xAB）：波形 `count=512`、样本字节数 = count×9、两块自洽；三场景全 PASS |

**实板一枪（证据 `release/evidence/trace85_board_wave/`，判据 21/21 PASS）**

```
ALIGN offset=1 anchor=1 delta=0 tied=[0, 2] cycles=512 retire=316 dv=97 rec=97 mismatch=0
```

**交叉校验是关键**：波形里 97 个 `d_req_valid & d_req_ready` 脉冲 ↔ 对齐区间内 97 条
load/store 指令，**差 0**。一条来自 Core 的握手线、一条来自提交记录，两条完全独立的
来源对上了，"按拍对齐"因此是**可证的**，不是画出来好看的。

**如实标注的三条限度**：对齐精度 **±1 条记录**（本枪 `tied=[0,2]`）；波形窗口只有
512/1024 拍（只覆盖 trace 的一段）；仍是**采集后回放**、不是实时流式。

**连带作废与重采**：tr85 的固件扩容让代码地址整体后移，所以
`release/evidence/trace85_board/` 的两枪在 2026-10-24 **重采**——结构数字全部不变
（100 条 / 19 个 PC / 每字符 12 条；4096 条 / 22 个 PC / 热点前四 99.49%），
但阶段 0 的具体 PC 值变了（`0x9BC…`→`0xDF0…`），README 已更新并写明原因。

**本轮踩的坑（详见 `docs/debug_log.md`）**：生成器把索引位宽写成 `log2(DEPTH)-1`，
2048 深的存储器只认 256 个字 → 取指全部别名 → **板子和仿真同时"CPU 跑飞、串口只剩噪声"**；
另有一处 `wait_mark` 标记长度数错（13 写成 15）导致 TB 永远匹配不上。

### 4.5 把"对齐"画到画面上 + 像素级冒烟（2026-10-24 下午，用户"感觉没啥变化"之后）

用户的反馈很直接："**我咋感觉效果没啥变化啊**"。核实后确认这不是错觉：
0xAB 让**能力**变了（波形与指令流同一次采集、可交叉校验），但**画面**没怎么变——
8 条探针泳道被按"和其它泳道一样的行距"压成了顶部约 56 px 的一条暗蓝带，
远看就是"又一排条纹"，而且波形和下面的指令块之间没有任何可见联系。改法：

| 改了什么 | 为什么 |
|---|---|
| 探针泳道**自己占固定高度**（8 × 11.5 px ≈ 92 px），不再从"统一行距"里挤 | 56 px 的色带在观感上等于没有 |
| 8 条泳道**按语义成对配色**：数据通道（请求/就绪）同蓝家族、取指通道（请求/就绪/响应）同紫家族 | 8 个互不相关的颜色像彩虹；成对配色能读出"这是同一条通路" |
| 画**阶跃沿**（上升/下降各一根提亮竖线），不再只是一根根色块 | 从"色带"变成"示波器" |
| 光标旁加**拍号气泡**（`拍47`）；底部状态行改成 `第 12–13 拍（2 拍后退休）` | 原来"第几拍"只存在于判据日志里 |
| **把对齐画出来**：选中一条指令时，它那一拍的**提交脉冲**、以及它**块内的数据访问脉冲**都标成白芯琥珀框 | 这是本页最该被看见的一根线：用户不必相信判据日志，眼睛就能对上 |
| **块的右边界改成"它退休的那一拍"**（原来从退休拍起算） | MEM 在自己的 WB 之前 ⇒ 访存指令的数据请求脉冲落在**自己的块里**。换算之后"每块有且只有一个数据访问脉冲"是肉眼可数的 |
| 采完自动选中**波形窗口里的第一条记录** | 原来默认选 #0，而 #0 在窗口之前 → 打开就是"不在波形窗口内"，什么标记都看不到 |
| 窗口档补 **2048 拍**，并新增判据"波形覆盖 trace 的绝大部分（≥95%）" | 512 拍只覆盖 316/323（97.8%）；2048 拍覆盖 1237/1247（99.2%，差的是 LA 采满后 trace 停止前那几条，如实计数） |
| 新增 `python/test_trace_ui_pixels.py`（4 项**像素级**冒烟） | 今天的两个 bug（`sel` 静默失效、泳道太矮"没变化"）都是**行为断言全绿、画面不对**。这层量的是画出来的东西：探针泳道总高 ≥80 px、每条泳道色块数与样本位数一致、光标落点 = 选中记录退休的那一拍、选中指令的寄存器行被框出 |

**2048 拍那一枪的实测**（`run_wave(..., window=3)`）：

```
window code=3 -> cycles=2048 records=1247 offset=1 retire_pulses=1237 cover=1..1237
dv=404 rec=404 mismatch=0        （判据 7/7 PASS）
```

**关于"±1 条记录"的处置（改了主意，如实记录）**：原计划加"哨兵"消除这 ±1，评估后**放弃**——
可行的做法只有两种：①故意写一个未映射地址制造 `error=1` 锚点（等于污染"未出错"的语义与既有判据）；
②靠语义猜测。两者都不如**如实标注**：现在界面、判据文本、证据 README 三处都写"候选 ±1 条"。

### 5. 本轮收尾状态

已完成：
1. SoC 级仿真两场景全 PASS（`GOT_MAX` 32768 → 65536）。
2. 实板两枪全 PASS；位流下载 `PROGRAM PASS config=tr85`。
3. `docs/application_logic_analyzer.md` **§6.11 已写完**（通路/记录格式/寄存器/命令/判据/边界/输入框/页面/验证入口）。
4. 实板证据归档在 `release/evidence/trace85_board/`（README + 两枪 log/html/json）。
5. 四条 trace 用例已加入 `scripts\run_final_regression.ps1`（缓冲单元 / MMIO+mux3 / Python 判据+输入框 / 端到端 SoC）。
6. **界面输入框**已落地并经**真界面路径**上板验证（见 §4.1）。
7. 全量回归 `ALL AUTOMATED FINAL REGRESSION PASS`（退出码 0），冻结范围审计 PASS。

仍待办（不影响本能力成立）：
1. `claims_map` 已加 trace85 条目（§15）；**la85 的 4 处哈希保持不动**。
2. 发布包（`export_final_submission` → `create_release_manifest` → `audit_release_package`）
   本轮未重跑；trace85 是附加演示位流，是否进交付包由用户决定。
3. `fpga/logic_analyzer/rtl/logic_analyzer_program.mem` 会被**当前**固件重新生成
   （跑 `run_logic_analyzer_board_top_tb.ps1` / `run_logic_analyzer_mirror_tb.ps1` 时）。
   这只影响 50 MHz 配置的**源码**，已冻结的 `la50`/`la85` 位流与哈希不变；
   但"从当前源码重建会得到不同固件"这件事必须如实记录。
4. 演示界面的 trace 入口**已接**（pyUI 的「提交级数据流」一栏），另有一键脚本
   `python\capture_trace.cmd`（会问你要发什么）与命令行 `trace_board.py --text`。

本轮顺带修掉的三处**工程性**问题（都不是 trace 功能本身）：
- `scripts/generate_logic_analyzer_fpga_memory.ps1`：`make/gcc` 往 stderr 打的
  `LOAD segment with RWX` 警告在 `$ErrorActionPreference='Stop'` 下会把脚本**就地打停**
  （表现是外面只看到 gcc 命令行 + 一条警告，退出码 1）。改为调用原生命令期间放开错误动作、
  一律按 `$LASTEXITCODE` 判定，退出码由 1 → **0**。
- 改过的 `.ps1`（含中文）必须补 UTF-8 BOM，否则 PowerShell 5.1 按 ANSI 解码后报
  "语法错误"。本轮被咬三次，已全部跑过 `scripts\ensure_ps1_bom.ps1`。
- 冻结范围审计原本只扫 `rtl / fpga/logic_analyzer / software/logic_analyzer / python`，
  **没扫新工程 `fpga/trace85`**；已加入扫描根（文件数 75 → 81）。审计同时拦下了
  `rtl/trace_buffer.v` 里一句"不做 RLE"的注释（纯关键词扫描不区分"做"与"不做"），
  已改写为"不做任何压缩"并在该处注明原因；**审计规则没有放宽**。

另发现一处**既有**文档不一致（不是本轮引入，未擅自改结论）：
`docs/interfaces.md` §5.1 写 `rtl/pipeline_cpu.v` 的 SHA-256 前缀为 `B58496706686E37B`，
而当前实际值是 `4759E3FD68A31CA20250D54345112CA1465C1035A24CB1C72E51905D5B2C7D17`
（M 扩展轮次改过该文件）。已在原处加"2026-10-21 复核更正"注记，
**端口/事务语义未变这条结论不变**，但哈希前缀不能再当证据用。

### 6. 引用纪律（写进材料前必须遵守）

- 在拿到实板 trace 之前，**不得**宣称"逻辑分析仪能展示 CPU 数据流"已完成；
  只能说"RTL/固件/上位机/位流已就绪，PDS 时序通过，板级待验"。
- 132 位记录里 `trace_mem_addr` **只在 store 时有效**（`trace_mem_we` 的语义就是"写存储"），
  所以 **load 地址不在记录里**；页面能显示 load 读到的值，地址只在基址寄存器
  于窗口内被写过时才推算，推不出来就显示 `?`。这一条必须原样写进材料与答辩。
- 不把本功能称为 PDS ILA，也不宣称替代它。

## 2026-10-28 提交代码包与用语清理

### 1. 做了什么

- 桌面生成 `RISC-V_CPU_2026_提交代码_20261028.zip`：2,444 个文件，未压缩 69.6 MB，
  压缩后 8.54 MB。内容为纯代码——`rtl/`、`tb/`、`software/`、`python/`、`scripts/`、
  `tests/`、`third_party/`，以及 `fpga/` 下 27 个工程的 rtl、constraints、`.pds`、
  `pds_recipe.tcl`、位流、布线后时序报告与厂商 IP 源码，外加一份顶层 `README.txt`。
  按用户决定，`docs/` 不进包。
- **上位机入口补回**：第一版把 `python/*.cmd` 整批排除了，导致带寄存器热力图的主界面
  （`python\pyUI.py`，页面②「CPU 数据流」）在包里没有入口。四个 `.cmd` 已放进包，
  其中三个原本把路径写成交付包的 `tools\` 布局、在源码树里跑不通，已改成仓库布局
  （`..\scripts\...` 与同目录 `pyUI.py`、`trace_board.py`），失败提示里的位流路径也换成
  `fpga\...` 实际位置。冒烟验证：包内 `ValidationUI()` 建成两个页签，
  含「CPU 数据流（寄存器热力图）」。README 增加「0) 打开上位机」一节。
- 清掉源码与脚本里的过程性黑话，共 72 个文件：`契约`改为`规范`/`验收条目`/`约定`，
  `冻结`改为`固定`/`保持不变`/`已归档`，`止损`改为`回退条件`/`取舍条件`，
  `闸门`改为`阶段检查`，`闭环`改为`端到端`，`打通`改为`跑通`/`已验证`，
  `经用户批准`改为`已确认`，代码里的 `Agent` 字样删除。
  **RTL 只改注释，没有动任何逻辑语句**；改完按 23 条词表复扫包内 2,265 个文本文件，0 命中。
- 包内 `README.txt` 的每条命令都实测过再写，其中三条按实测更正：
  `check_coremark_elf.ps1` 必须带 `-Disassembly`/`-Attributes`；
  `逻辑分析仪演示.py --selftest` 同样要接开发板；上位机依赖 pyserial 3.5。

### 2. 顺手修掉的一处既有问题

`scripts/run_scope_audit.ps1` 原为 UTF-8 无 BOM。PowerShell 5.1 按 ANSI(936) 解码时
会把换行吞掉（实测 83 行读成 72 行），脚本里的前置检查与 `throw` 行号全部错位，
该审计必然失败。已补 BOM；全仓 `scripts/*.ps1` 现在都带 BOM。

### 3. 验证（都在解压出来的包目录里跑，不是开发仓库）

- `scripts\run_pipeline_regression.ps1`：ALL PIPELINE REGRESSION PASS（13 项）
- `scripts\run_rv32i_regression.ps1`：ALL RV32I REGRESSION PASS
- `scripts\run_coremark_pipeline_tb.ps1`：ALL COREMARK PIPELINE TEST PASS，
  cycles=1,251,724、retired=786,925，与包内 README 印的数字一致
- `run_trap_pipeline_tb`、`run_trap_golden_judge`、`run_csr_unit_tb`、`run_timer_irq_tb`、
  `run_mdu_tb`、`run_pipeline_m_ext_tb`、`run_ras_tb`、`run_cpi_attribution_tb`、
  `run_logic_analyzer_tb`、`run_logic_analyzer_board_top_tb`、`run_logic_analyzer_mirror_tb`、
  `run_trace_buffer_tb`、`run_core_trace_mmio_tb`：全 PASS
- `scripts\run_scope_audit.ps1`：SCOPE AUDIT PASS（补 BOM 之后）
- `scripts\generate_coremark_fpga_memory.ps1`：COREMARK FPGA MEMORY GENERATED
- `python -m py_compile`、`.ps1` 语法解析、`node --check`：改过的文件全 PASS

### 4. 有意没动的部分

- `docs/`、`AGENTS.md`、`AGENTS.local.md` 里的过程用语保留原样：它们是开发记录与规则文件，
  不进提交包，改写它们会破坏证据链。
- `scripts/apply_scope_change.py` 没进包：它是文档迁移用的一次性脚本，通篇在讲内部流程。
  `python/*.cmd` 这一版已进包并修好路径（见 §1），不再排除。
- RTL/TB 注释里"不是 A，而是 B"的对比句留了 8 处，它们承担真实对照，不是话术。
- 厂商 IP（`fpga/*/ip/**`、`pds_ip_probe/rtl/ips_*`）没改：里面有加密保护声明，改了就坏。

## 2026-10-28 追加：寄存器写回热力图改为复用现有上位机（不另写一份）

### 1. 经过

用户先指出交付包里的 `逻辑分析仪演示.py` 没有寄存器写回热力图，随后明确纠正：
既然 `python/mes50hp_validation_ui.py` 第 2 页早就有这个热力图，就直接用它，不要另写一份。
第一版我在单文件里独立实现了一遍（协议 + 解析 + 反汇编 + Canvas 画图 + HTML 导出，约 810 行），
虽然自检与交叉验证都过了，但**两份实现必然走形**，已整段删除：
文件从 2576 行回到 1766 行（原始 1702 行 + 跳转入口）。

### 2. 现在的做法

- `python/mes50hp_validation_ui.py` 只加两个小口子，热力图本身一行没动：
  - `--trace-log PATH`：离线回放一枪保存下来的 0xAA 回包，第 2 页照样出图，不需要开发板；
  - `ValidationUI._load_trace_log()`：走的是与真采集**同一套**
    `parse_capture / build_flow / judge / summarise`，只多一步"从文件读回包"；
    结果投进既有事件队列，由 `_poll_events` 在 UI 线程里画。
- `python/samples/trace_hello_rv.log`：2026-10-24 板上跑 `hello,rv` 的真实回包
  （100 条记录 / 8 个打点），供离线回放。
  **2026-10-28 修正**：此前这份文件实际停留在 2026-10-23 那一版固件（PC 整段比现在低 0x434），
  已换成 `release/evidence/trace85_board/trace_phase0.log` 的逐字节副本，与当前
  `fpga/trace85/rtl/logic_analyzer_program.mem` 判据 **15/15 PASS**；配对关系与自检命令见
  `python/samples/README.md`。
- `逻辑分析仪演示.py` 新增 `find_pyui()` / `sample_trace_log()` / `open_full_ui()`，
  顶部按钮改成「▶ CPU 数据流（寄存器热力图）」：点子进程打开 pyUI 第 2 页，
  没有板子时顺带离线回放上面那份样本。演示程序里不再有任何热力图绘制代码。

### 3. 验证

- 包内（解压后）检查：`find_pyui()` / `sample_trace_log()` 均指向包内文件；
  `open_full_ui` 起的命令与工作目录正确；第 2 页离线回放出 **100 条记录、
  324 个矩形（焊点）**，选中第 42 条得 `lbu x15,0(x8)`。
- `python python/mes50hp_validation_ui.py --page 2 --trace-log python/samples/trace_hello_rv.log`
  实起一次：进程在跑（参数被接受、窗口起来了），验证后已关闭；`--page 9` 会被 argparse 拒绝。
- 既有测试全绿：`test_logic_analyzer_ui` + `test_trace_ui` 共 39 项 OK、
  `test_logic_analyzer_singlefile` 6 项 OK、`singlefile_protocol_check.py` PASS。

### 4. 踩到的坑

- `probe` 回调的实参个数不能改：既有测试按 7 个参数回调，我一度加了第 8 个，
  `after` 回调里抛 TypeError，整个测试超时。入口统一挂在 `st["open_trace"]` 上。
- 离线回放要先把 notebook 切到第 2 页再画：页面没显示时画布宽度是 0，
  `_tl_geom()` 只算得出几个像素的视窗（第一版验证脚本就是这么假失败的）。

### 5. 交付包的 UI 入口改为 pyUI（2026-10-28 收尾）

用户明确要求：包里只放"之前那份含热力图的完整 UI"，旧的单文件演示程序不要。

- 打包清单里删掉 `逻辑分析仪演示.py`，包根目录只剩 `README.txt`；上位机入口为
  `python\pyUI.py`，页面②就是寄存器写回热力图。
- `python/pyUI.py` 改成不带参数即 `--page 2 --trace-log samples/trace_hello_rv.log`，
  所以双击它直接停在热力图页，并且已经离线回放一枪真实记录（100 条），没有板子也有图；
  带参数时行为不变（例如 `--page 1` 仍是八通道波形页）。
- 包内验证（解压后）：无 `*演示.py`；`pyUI.py` 默认参数正确；第 2 页 100 条记录、
  324 个矩形焊点；选中第 7 条得 `sw x15,0(x12)`；`python pyUI.py` 起得来且不退出。
- 仓库里的 `逻辑分析仪演示.py` 暂时保留：`singlefile_protocol_check.py`、
  `test_logic_analyzer_singlefile.py` 与 `export_final_submission.ps1`、
  `audit_release_package.ps1`、`build_submission_bundle.ps1`、`run_ui_source_board.ps1`
  都指向它，直接删会让回归与导出脚本报错。工具链里这一条留待用户确认后一并处理。
- 另外记一笔排查结论：单文件版里 `<<TreeviewSelect>>` 会自己触发自己
  （回调里再 `selection_set`），Tk 事件队列永远清不空、窗口卡死；
  用"已经是那一行就不再 selection_set"的幂等写法修掉（该文件现已不在交付包内）。
### 6. 上位机入口提到包根目录（2026-10-28 收尾）

用户要求把 UI 放到醒目位置。做法是在包根目录放一个 `pyUI.py`（1.4 KB，只有入口逻辑）：
把 `python/` 加进 `sys.path` 后调用 `mes50hp_validation_ui.main()`，
**不复制任何 UI 代码**；界面本体仍然是 `python/mes50hp_validation_ui.py` 那一份。
不带参数时传 `--page 2 --trace-log python/samples/trace_hello_rv.log`，
所以双击包根目录的 `pyUI.py` 直接落在寄存器热力图页且已有数据。

包内验证（解压后）：根目录只有 `pyUI.py` 与 `README.txt`；默认参数正确；
第 2 页 100 条记录、324 个矩形焊点；从包根目录起进程能存活。
### 7. "双击打不开"的真实原因与修法（2026-10-28 收尾）

用户报告双击 pyUI.py 报错。逐项排查后确认是两件环境事实，都不是代码 bug：

1. 这台机器上 `.py` 的默认打开方式是 VS Code：
   `AssocQueryString(ASSOCSTR_COMMAND, ".py")` = `"D:\Microsoft VS Code\Code.exe" "%1"`。
   双击 .py 只会把文件在编辑器里打开，不会运行它；VS Code 本来就在跑，
   所以连新进程都不会出现。注册表里 `HKCU\Software\Classes\.py` 是 `Python.File`、
   `Python.File\shell\open\command` 是 py.exe，但实际优先级被 VS Code 的
   `Applications\Code.exe` 与 `FileExts\.py\OpenWithList` 抢走（无 UserChoice）。
2. 桌面上当时**没有解压目录**，只有 zip。在资源管理器"压缩文件夹预览"里双击，
   系统只放出单个临时文件，旁边的 `python\` 不在，于是必然 ModuleNotFoundError；
   双击时窗口一闪就没，所以用户只看到"报错"。

处理：
- 包根目录放 `双击我-打开上位机.lnk`：目标 `py.exe`，参数与起始位置用
  `%USERPROFILE%\Desktop\RISC-V_CPU_2026_提交代码\`（实测 .lnk 参数里的环境变量会展开）。
  双击 .lnk 永远执行目标，与 .py 关联无关。
- `pyUI.py` 加自诊断：找不到 `python/mes50hp_validation_ui.py` 时打印中文说明并
  `input()` 停住，不再一闪而过。
- 排查期间曾临时改过 `HKCU\Software\Classes\.py`（并把 OpenWithList 备份后删掉）；
  **已用 reg export 的备份原样回滚**，`.py` 仍是 VS Code，临时建的 `PyScriptRun` 已删除。
- 验证：把最终 zip 解压到桌面默认目录，ShellExecute 包内那个 .lnk →
  python 带 `Desktop\RISC-V_CPU_2026_提交代码\pyUI.py` 起来并存活；
  之前已单独验证该 pyUI 默认参数为第 2 页 + 回放样本，页面 100 条记录 / 324 个焊点矩形。

## 2026-10-28 第 ② 页离线回放与交付包收口（用户授权"全修"）

用户看演示素材时报告"第二页的热力图是写死的"。核查结论：**画图不是写死的**
（四条泳道全部由 `trace_nodes` 现算，无数据时显示"还没有数据 —— 填字符串，然后点「采集」"），
但"看起来是写死的"这个判断成立，因为它周围有四个真问题：

1. 默认入口固定喂一份 **2026-10-23 的旧固件录包**，每次打开都是同一张图；
2. 那份录包与当前 `fpga/trace85/rtl/logic_analyzer_program.mem` **不同源**（PC 整段差 0x434），
   于是 `pc 与位流镜像同源` 100 条全错，状态栏常驻 `FAIL`；
3. 回放路径把回包 `TRACE TEXT`（已大写化）当成"发送的字符"，稳定多出 2 条假 FAIL；
4. 第 ② 页没有任何"这是回放"的标识（提示只进了第①页的日志框），
   且交付包里**根本没有第 ② 页**（缺 `trace_view.py`/`trace_board.py`，包内 UI 是 40 KB 旧版）。

用户当日批准"全修"。本轮**不改任何 RTL、不改 `pipeline_cpu.v`、不重打位流、不改任何位流哈希**。

### 1. 改动清单

| 文件 | 改动 | 为什么 |
|---|---|---|
| `python/samples/trace_hello_rv.log` | 换成 `release/evidence/trace85_board/trace_phase0.log` 的**逐字节副本** | 归档证据与当前镜像 **15/15 PASS**，旧样本 100 条 PC 全不一致 |
| `python/samples/README.md`（新增） | 记录来源、`hello,rv`、100 条/8 打点、样本 SHA、镜像 SHA、自检命令 | 样本与镜像是"一对"，配对关系必须写在样本旁边 |
| `python/mes50hp_validation_ui.py` | ①`_load_trace_log` 的 `sent` 改为从打点还原（新增 `phase` 参数与 `--trace-phase`）；②`_show_trace` 识别 `payload["replay"]`，置/撤「离线回放」徽标，判据标题与状态栏写明"离线回放/仅供参考"；③新增 `_set_trace_replay()` | 消掉 2 条假 FAIL；让"放录像"与"板子刚采的"一眼可分 |
| `python/start_logic_analyzer.cmd` | 自动探测 `pyUI.py` / `tools\pyUI.py`，显式 `--page 1` | 原版写死 `pyUI.py`，在交付包根目录必然报"找不到文件" |
| `python/start_logic_analyzer_offline.cmd`（新增） | 第 ② 页离线回放入口，样本两处布局都能找到 | 真采集与离线演示拆成两条入口，不再靠"默认行为"隐式区分 |
| `scripts/export_final_submission.ps1` | 增补 `python/samples/` → `tools/samples/`、`离线演示.cmd`；README 段说明两条入口 | 包里没有样本，第 ② 页在评委机上只有一句"还没有数据" |
| `scripts/audit_release_package.ps1` | `$required` 加 `tools/trace_view.py`、`tools/trace_board.py`、`tools/samples/trace_hello_rv.log`、`离线演示.cmd` | 2026-10-22 就加了 trace 文件拷贝但包没重导，审计没拦住 ⇒ 把它写进必检清单 |
| `scripts/make_desktop_shortcuts.ps1` | 加一条 `06b_上位机_离线演示_无板可看.lnk`（未运行该脚本） | 桌面出口与新增入口保持一致 |
| `python/test_trace_ui.py` | 新增 `OfflineReplaySampleTests`（3 项）与 `ReplayBannerTests`（3 项） | 钉住"样本↔镜像同源""sent 必须取打点""徽标置/撤"三件事 |

### 2. 验证（实际执行的命令与结果）

```powershell
# ① 样本 ↔ 镜像同源（headless，不需要板子）
cd python; python -c "import trace_view as tv; from pathlib import Path; cap=tv.parse_capture(Path('samples/trace_hello_rv.log').read_bytes().decode('utf-8','replace')); sent=''.join(chr(m['value']) for m in cap['marks']); im=tv.load_program_mem(Path('../fpga/trace85/rtl/logic_analyzer_program.mem')); r=tv.judge(cap,sent,0,im,depth=4096); print(tv.judgements_pass(r), [n for n,ok,_ in r if not ok])"
# 修前：旧样本用当前镜像 → FAIL（pc 同源 100 条不一致）；用回包文本当 sent → 3 条 FAIL
# 修后：True []（15/15 PASS）

# ② 上位机测试
cd python; python test_trace_ui.py           # Ran 34 tests ... OK（含新增 6 项）
cd python; python test_trace_ui_pixels.py    # Ran 4 tests ... OK
cd python; python test_logic_analyzer_ui.py  # Ran 11 tests ... OK

# ③ 启动入口四种布局实测（假 pyUI 只打印 argv）
#   仓库布局（pyUI.py 同级）：live ['--page','1'] / offline ['--page','2','--trace-log','samples\\trace_hello_rv.log']
#   交付包布局（仅 tools\pyUI.py）：live ['--page','1'] / offline ['--page','2','--trace-log', ...]
#   样本缺失：打印中文提示后落 --page 2（空白页，不崩）

# ④ 交付链（2026-10-14 之后首次重跑）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\export_final_submission.ps1
#   FINAL SUBMISSION EXPORT PASS files=315 zip=release\MES50HP_RISCV_Logic_Analyzer_Final.zip
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\create_release_manifest.ps1
#   RELEASE MANIFEST PASS files=4092
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\audit_release_package.ps1
#   RELEASE PACKAGE AUDIT PASS final_files=316 artifacts=3

# ⑤ 演示自检（只读）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\demo_preflight.ps1 -Port COM11
#   DEMO PREFLIGHT PASS warnings=0（demo files 13 entries present）
```

包内抽查：`tools/trace_view.py`、`tools/trace_board.py`、`tools/trace_viewer.html`、
`tools/capture_trace.cmd`、`tools/trace_ui_board_check.py`、`tools/samples/trace_hello_rv.log`、
`tools/samples/README.md`、`离线演示.cmd` 全部在包内；包内 `tools/pyUI.py` 是带默认回放的版本
（`--page 1` 才走真采集）。

### 3. 本轮没做的事（如实列出）

- **没有上板重录样本**：归档证据 `trace_phase0.log` 与当前镜像逐条 PASS；它本身就是登记在
  `claims_map.md` §15 的实板证据，换包不换数据。若以后重打 trace85 位流，必须按
  `python/samples/README.md` 的自检命令复核，或重新采一枪。
- **没有手点 GUI 截图验证徽标外观**：徽标的"置/撤"由 `ReplayBannerTests` 断言
  （`winfo_manager()` 为 `pack` / 空），外观留待录屏时目视一次。
- `scripts/make_desktop_shortcuts.ps1` 只改了定义、**没有运行**（它会往桌面写快捷方式）。
- 顺带修的两处环境坑（`.ps1` 需 UTF-8 BOM、`.cmd` 需 CRLF）只覆盖本次涉及的文件，
  详见 `docs/debug_log.md` 2026-10-28 的附录。

### 4. 对演示视频素材的影响（必须遵守）

- 第 ② 页「寄存器热力图」**只能现场真采一枪才准上镜**：双击 `离线演示.cmd` 出来的画面顶部有
  「离线回放」徽标，那是录像，不能当"板子此刻在跑"的证据。
- 现场真采需要板子跑 `trace85` 位流（不是交付位流 `la85`）：`scripts\run_trace85_pds.ps1` 建、
  `scripts\program_board.ps1` 下载后，用 `启动逻辑分析仪.cmd` 或 `pyUI.py --page 1` 进第①页，
  再到第②页点「采集」。拍完记得把板子恢复成交付位流 `la85`。

## 2026-10-30 上位机收口：只保留一个 py 文件（用户明确要求）

> 用户原话："不要把 py UI 文件分布放置，我要一个 py 文件能实现所有功能。"
> 此事自 2026-10-10 起已被要求多次，但前几轮把"完整 UI（含热力图）"做成了
> `python/mes50hp_validation_ui.py` + 5 个模块的多文件结构，并把单文件版判为"重复实现"而弃用。
> 这是**判断错误**：单文件版 `逻辑分析仪演示.py` 一直在仓库根目录，且功能覆盖更全。

### 1. 唯一用户入口

| 用途 | 文件 | 说明 |
|---|---|---|
| **唯一上位机** | `逻辑分析仪演示.py`（仓库根目录，146 KB） | 自包含单文件，只依赖 `pyserial`；五种采集模式 + 双采集源 + 仪器面板 + 波形 + 仪器读数 + VCD/HTML/Markdown 报告 + **CPU 数据流（逐条指令 + 寄存器写回热力图）** |
| 跳板 | `pyUI.py`（根目录） | 只剩 30 行：`runpy` 拉起上面那个文件，自己不再实现任何功能 |
| 启动器 | `python/start_logic_analyzer.cmd`（交付包 `启动逻辑分析仪.cmd`） | 拉起单文件；仓库布局（`python\` 下）与交付包布局（根目录）都自动定位 |
| 启动器 | `python/start_logic_analyzer_offline.cmd`（交付包 `离线演示.cmd`） | `--trace` 直接开「CPU 数据流」窗口，点『示例数据』即可看热力图，**不需要板子、不需要样本文件** |

多文件那套（`python/mes50hp_validation_ui.py`、`trace_view.py`、`trace_board.py`、
`logic_analyzer*.py`、`waveform_panel.py`）**保留但不再是入口**：它们现在是
`test_trace_ui.py` / `test_trace_ui_pixels.py` / `test_logic_analyzer_ui.py` 的被测对象，
删掉会让回归断链。

### 2. 本次给单文件补齐的功能（此前只有多文件版有）

| 补齐项 | 内容 |
|---|---|
| **13 条 trace 判据** | 新增 `expected_phase0` / `sent_text_from_marks` / `judge_trace` / `judgements_pass`；`TraceWindow` 底部新增「判据（这一枪可不可信）」面板，逐条列 PASS/FAIL，标题行给 `n/n` 汇总 |
| **示例/实时来源标识** | 状态栏与判据标题都写明来源：`示例数据（离线，不是本机板子）` / `实时采集（本机板子）`，避免把内置样例当成板子刚采的 |
| **判据口径修正** | `sent` 一律取**打点值**（`sent_text_from_marks`），不用回包 `TRACE TEXT`（那是大写化之后的，会白报 2 条 FAIL） |
| **内置样例换成当前固件同源的那一枪** | 原内置样片是 **32 条节选**且打点值是大写化之后的：`打点索引` 越界（索引 4…39 > count 32）、`大写字符计数` 也对不上，判据一上就假失败。现替换为 `release/evidence/trace85_board/trace_phase0.log` 全文（100 条 / 8 打点 / `status=0x4`，与 `fpga/trace85/rtl/logic_analyzer_program.mem` 同源） |

### 3. 验证（实际执行）

```powershell
python "逻辑分析仪演示.py" --trace-selftest
#   TRACE SELFTEST PASS（20 项）：解析 100 条 / 8 打点 / 发送文本取打点值 'hello,rv'
#   / 判据全部通过（13 条）/ 用回包文本判据必然报错 / 反汇编 12 条 / 59 个写回方格
#   / 画图与空数据不崩 / 导出网页 45176 字节

python python\test_logic_analyzer_singlefile.py     # Ran 6 tests ... OK
python python\singlefile_protocol_check.py         # SINGLE FILE CHECK PASS
python pyUI.py --trace-selftest                    # 跳板可用，同上 PASS

# 启动器四种布局实测（假 app 打印 argv）
#   仓库布局 python\*.cmd：live [] / offline ['--trace']
#   交付包布局 根目录 *.cmd：live [] / offline ['--trace']

scripts\export_final_submission.ps1   # FINAL SUBMISSION EXPORT PASS files=315
scripts\create_release_manifest.ps1   # RELEASE MANIFEST PASS files=4092
scripts\audit_release_package.ps1     # RELEASE PACKAGE AUDIT PASS final_files=316
```

包内自查：`release/final_submission/逻辑分析仪演示.py` 与仓库版**哈希一致**
（`B1A00302…`，146,192 字节）；`启动逻辑分析仪.cmd` / `离线演示.cmd` 都指向它。

### 4. 未做 / 边界

- 单文件版**没有**多文件版的三样东西：`0xAB` 波形+指令按拍对齐、四组泳道时间轴（寄存器/PC/写存储/事件）+ 播放条、
  `--page` 命令行选页（单文件用「示例数据」按钮和 `--trace` 开关代替）。这三样是锦上添花，
  要不要补进单文件由用户决定——补的话仍然只改这一个文件。
- 单文件**不判断"样本与固件镜像同源"**：它的助记符直接由记录里的指令字反汇编，不依赖任何外部镜像，
  所以那条判据在本文件里不存在（多文件版的 15 条里那条也不适用）。
- 本轮未改任何 RTL、未重打位流、未改位流哈希、未动 `pipeline_cpu.v`。
