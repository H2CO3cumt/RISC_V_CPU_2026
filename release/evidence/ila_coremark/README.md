# CoreMark 实体板 ILA 波形证据（赛题「利用 ILA 波形分析流水线效率」）

本目录是赛题「技术实现与文档 → 分析报告」一项的实体板素材：用 PDS **Fabric Debugger**
在 MES50HP 上抓取 CPU 执行 CoreMark 时的真实流水线波形。

## 1. 采集配置

| 项 | 值 |
|---|---|
| 工程 | `fpga/coremark_ila`（`mes50hp_coremark_top` + 192-bit DebugCore + Jtag Hub） |
| 位流 | `fpga/coremark_ila/generate_bitstream/mes50hp_coremark_top.sbit` |
| 位流 SHA-256 | 见同目录 `coremark_ila_summary.json` 所在构建日志（`pds_build.log`） |
| 程序镜像 | 官方 CoreMark，ITERATIONS=1000、50 MHz、串口 `R` 启动（与计分镜像同一份） |
| 采样 | 50 MHz，512 拍（10.24 µs），单窗口，运行中立即触发 |
| 探针 | 192-bit：提交 PC/指令/寄存器写回/Store、stall/load-stall/branch/taken/flush、reset、D/R 事务握手 |
| 工具 | `cdt_dbg.exe`（Fabric Debugger TCL 模式），命令序列见 `ila_capture.tcl` |

采集流程（可复现）：

```powershell
# 1) 构建诊断位流
& '<pwsh7>' -NoProfile -File scripts\run_coremark_ila_pds.ps1
# 2) 启动 JTAG 服务
Start-Process 'D:\Pango\PDS_2024.2-SP2\bin\cdt_js.exe' -ArgumentList '-work_dir','D:\RISC_V_CPU_2026\tmp','-port','65420'
# 3) 一边持续发 'R' 启动 CoreMark（并记录串口输出），一边用 Fabric Debugger 抓波形
D:\Python313\python.exe tmp\ila\send_r.py tmp\ila\uart_during_capture.log 900
& 'D:\Pango\PDS_2024.2-SP2\bin\cdt_dbg.exe' -file tmp\ila\capture4.tcl
# 4) 生成分析证据
D:\Python313\python.exe python\ila_coremark_analysis.py --capture tmp\ila\coremark_ila.txt `
  --dis software/coremark/build/coremark.dis --outdir release/evidence/ila_coremark
```

## 2. 结果（`coremark_ila_summary.json`）

| 指标 | 波形窗口 | 板级计数器（整段运行） |
|---|---:|---:|
| 采样拍数 | 512 | 1,112,164,751 |
| 提交指令 | 325 | 722,746,356 |
| **IPC** | **0.635** | 0.650 |
| **CPI** | **1.575** | **1.5388** |
| stall 拍 | 7 | 90,967,358 |
| load-use stall 拍 | 0 | 21,170,296 |
| branch / taken | 100 / 65 | 198,565,070 / 123,391,685 |
| flush | 44 | 74,612,760 |

窗口 CPI 与整段板级 CPI 相差 2.3%，说明这 512 拍是可代表整体行为的稳态窗口。

> ⚠️ **批次说明（2026-09-30 补注，务必先读）**
>
> 本目录的**全部数字属于 2026-09-17 那一批位流**：波形来自 `fpga/coremark_ila/generate_bitstream/`
> （构建于 2026-09-17 20:44），右侧"板级计数器"一列来自**同批**的 `release/evidence/coremark_board_cpi50m.json`
> （Score 45.051 / CPI 1.5388）。**"相差 2.3%"这个对比只在同批次内成立。**
>
> 当前交付批次的 CoreMark 位流是 `release/evidence/coremark_board.json`
> （2026-09-29，`ticks=1068006999`、Score **46.816**、CoreMark/MHz **0.936**、CPI **1.508**）。
> **拿 1.508 去比这里 09-17 的波形，差值是 4.5%，不是 2.3% —— 两个数不得混用。**
>
> 若要引用"窗口 vs 整段"的对比，必须同时说明两边分别是哪一批；
> 跨批次引用是本项目材料收口时发现的主要风险，来源见 `release/evidence/claims_map.md` §12。
>
> 另外注意：这里的 **512 样本**是 **PDS DebugCore 探针**的窗口；
> 作品自带的八通道逻辑分析仪 Raw 深度是 **256 样本**，两者不是一回事。

## 3. 关键发现：CoreMark 的时间花在软件乘法循环里

窗口内 **84.3% 的提交指令（274/325）落在 `__mulsi3`**：

| PC | 次数 | 指令 | 说明 |
|---|---:|---|---|
| `0x00003520` | 49 | `andi a3,a1,1` | 取乘数最低位 |
| `0x00003524` | 48 | `beq a3,zero,352c` | **数据相关分支**：决定是否累加 |
| `0x00003528` | 28 | `add a0,a0,a2` | 累加（28/48 次执行） |
| `0x0000352c` | 48 | `srli a1,a1,0x1` | 乘数右移 |
| `0x00003530` | 48 | `slli a2,a2,0x1` | 被乘数左移 |
| `0x00003534` | 48 | `bne a1,zero,3520` | 循环分支（全部 taken） |
| `0x00003538` | 1 | `jalr zero,0(ra)` | 返回 |

结论与可行动性：

1. **RV32I 没有硬件乘法器**，CoreMark 的矩阵运算全部走 libgcc 的移位加 `__mulsi3`；
   该循环在窗口内迭代 48 次、约 10.7 拍/次（5.7 条指令），是本窗口的绝对主体。
   这也是 CoreMark 在 RV32I 上「算得多、跑得慢」的结构性原因（属 ISA 选择，不是流水线缺陷）。
2. **该循环的 `beq` 是数据相关的**（48 次里 28 次不跳、20 次跳），2-bit 饱和计数器难以预测，
   是窗口内 44 次 flush 的主要来源 → 与 `docs/coremark_cpi_analysis.md` 中
   「flush 已是当前最大单项、且 mispredict 为主要成分」的板级统计互相印证。
3. `bne`（循环回边）在 16 项 BTB 命中良好，说明循环控制本身不是瓶颈；瓶颈在数据相关分支。

## 4. 文件说明

| 文件 | 内容 |
|---|---|
| `coremark_ila_raw.txt` | Fabric Debugger 原始导出（512 行 × 30 列） |
| `coremark_ila_512cycle.csv` | 带信号名的逐拍表（30 列） |
| `coremark_ila_512cycle.vcd` | 同一窗口的 VCD，可在任意波形查看器中回放 |
| `coremark_ila_cycle_table.txt` | 第一个 flush 前后 24 拍的可读逐拍表 |
| `coremark_ila_summary.json` | 自动生成的汇总（IPC/CPI/事件计数/热点 PC/符号名） |
| `ila_capture.tcl` | 本次抓取使用的 Fabric Debugger TCL 脚本 |
| `ila_capture_console.log` | 抓取过程控制台记录（含 FIC 导入、触发、导出） |
| `uart_during_capture.log` | 抓取期间串口原文（CoreMark 结果与 `COREMARK_DONE`） |

> 探针位段与 `fpga/coremark_ila/README.md` 的 192-bit 布局一一对应；
> 分析脚本 `python/ila_coremark_analysis.py` 按该布局解码，并校验 `memory_ready` 恒为 1、`reset` 恒为 0 以自证列映射正确。
