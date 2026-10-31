# 设计文档插图索引

> 用途：设计文档所有插图的唯一登记处。图号与 `docs/design_document.md` 骨架一致。
> 生成方式：`.drawio` 手写坐标源文件 → draw.io 31.1.8 命令行导出 `.svg` 与 `.png`。
> 插图进文档的动作**等正文定稿后**再执行，当前只做图。

## 1. 配色与线型约定（全篇统一）

### 1.1 分区底色

| 语义角色 | 边框 | 底色 | 代表模块 |
|---|---|---|---|
| 计算核心 | `#C86F17` / `#D9822B` | `#FFD9B0` 加深，浅底 `#FFE9D2` | 处理器核、FPGA 主器件 |
| 基础支撑 | `#2E6FB7` | `#CCE2F7` | 时钟、电源、互连、配置 |
| 存储与外设 | `#2E7D32` | `#D8EEDA` | RAM、UART、GPIO、定时器、按键 LED |
| 采集应用 | `#6335C6` / `#7A4FD0` | `#D6C2F5` 加深，浅底 `#E7DBFA` | 逻辑分析仪、性能监视器、MMIO |
| 板外与外部设备 | `#5F5F5F` | `#EDEDED` | PC、下载器、被测信号 |
| 未启用 | `#8C8C8C` 虚线 | `#F2F2F2` | 备用时钟等本届不用的资源 |

### 1.2 线型语义

| 线型 | 颜色 | 含义 |
|---|---|---|
| 实线 | 蓝 `#2E6FB7` | 数据与事务通路 |
| 虚线 | 蓝 | MMIO 访问 |
| 虚线 | 橙 `#C86F17` | 核发出的提交与观测事件 |
| 虚线 | 红 `#C0392B` | 中断 |
| 虚线 | 紫 `#7A4FD0` | 采集应用内部链路 |
| 实线 | 灰 `#5F5F5F` | 板外串行链路 |
| 虚线 | 灰 `#8C8C8C` | 本届未启用的资源 |

### 1.3 字体

- 中文：Microsoft YaHei，标签 15 px，分区标题 16 px 加粗，线标签 13 px。
- 图内文字一律用对外表述，不出现文件路径、模块文件名、工具名、内部流程名（`writing_style.md` §8）。

## 2. 图纸清单

### 2.1 已完成

| 图号 | 标题 | 源文件 | 导出 | 尺寸 | 对应章节 |
|---|---|---|---|---|---|
| 图 2-1 | 系统整体框图 | `src/fig2_1_system_overview.drawio` | `build/fig2_1.svg` / `.png` | 5188×3448 | 2.1 |
| 图 2-2 | 硬件整体框图 | `src/fig2_2_hardware_overview.drawio` | `build/fig2_2.svg` / `.png` | 2846×1627 | 2.2.1 |
| 图 2-3 | 板级信号连接与引脚图 | `src/fig2_3_board_pinout.drawio` | `build/fig2_3.svg` / `.png` / `_hi.png` | 4892×2429 | 2.2.3 |
| 图 2-4 | 软件整体架构图 | `src/fig2_4_software_arch.drawio` | `build/fig2_4.svg` / `.png` / `_hi.png` | 5342×2608 | 2.3.1 |
| 图 1-1 | 设计流程图 | `src/fig1_1_design_flow.drawio` | `build/fig1_1.svg` / `.png` / `_hi.png` | 3988×1828 | 1.6 |
| 图 2-5 | 取指与分支预测流程图 | `src/fig2_5_fetch_predict.drawio` | `build/fig2_5.svg` / `.png` / `_hi.png` | 3439×3560 | 2.3.2 |
| 图 2-6 | 译码、冒险与前递流程图 | `src/fig2_6_decode_hazard_forward.drawio` | `build/fig2_6.svg` / `.png` / `_hi.png` | 3510×3928 | 2.3.2 |
| 图 2-7 | 执行与乘除流程图 | `src/fig2_7_execute_mdu.drawio` | `build/fig2_7.svg` / `.png` / `_hi.png` | 2926×3778 | 2.3.2 |
| 图 2-8 | 访存与异常提交流程图 | `src/fig2_8_mem_trap.drawio` | `build/fig2_8.svg` / `.png` / `_hi.png` | 4078×3598 | 2.3.2 |
| 图 2-9 | 采集引擎与 MMIO 流程图 | `src/fig2_9_capture_mmio.drawio` | `build/fig2_9.svg` / `.png` / `_hi.png` | 4108×3838 | 2.3.2 |
| 图 2-10 | PC 端采集与解析流程图 | `src/fig2_10_pc_capture.drawio` | `build/fig2_10.svg` / `.png` / `_hi.png` | 4189×3659 | 2.3.2 |
| 图 3-5 | CoreMark Predictor 前后对比 | `src/fig3_5_coremark_predictor.drawio` | `build/fig3_5.svg` / `.png` / `_hi.png` | 2986×1622 | 3.3 |
| 图 3-6 | CPI 分解 | `src/fig3_6_cpi_breakdown.drawio` | `build/fig3_6.svg` / `.png` / `_hi.png` | 2707×1222 | 3.3 |
| 图 3-7 | 工作频率与分数、时序余量 | `src/fig3_7_freq_score.drawio` | `build/fig3_7.svg` / `.png` / `_hi.png` | 2795×1462 | 3.3 |
| 图 3-8 | 五模式板级采集结果 | `src/fig3_8_mode_capture.drawio` | `build/fig3_8.svg` / `.png` / `_hi.png` | 2702×1190 | 3.3 |
| 图 3-9 | 关键数据汇总表 | `src/fig3_9_data_summary.drawio` | `build/fig3_9.svg` / `.png` / `_hi.png` | 2706×3510 | 3.3 |
| 图 3-10 | 关键指标卡（4×3 卡 + 止损条） | `src/fig3_10_key_metrics.drawio` | `build/fig3_10.svg` / `.png` / `_hi.png` | 2770×1858 | 3.3 |
| 图 3-11 | 基础任务、进阶任务与额外做的（M 扩展单列） | `src/fig3_11_completion_status.drawio` | `build/fig3_11.svg` / `.png` / `_hi.png` | 2912×2038 | 3.1 |
| 图 3-4 | 上位机界面截图 | 由证据页面离屏截取，无 `.drawio` | `build/fig3_4.png` | 3360×2100 | 3.2.3 |

**19 张插图全部完成**（11 张 drawio + 7 张数据图 + 1 张界面截图），每张都做过视觉检查。

图 3-4 的取得方式：`release/evidence/logic_analyzer_board_85m/uart/uart_00.html` 是板级实测证据自动生成的单文件波形页，
用 Edge 无头模式 2 倍像素密度离屏截图，命令为：

```powershell
& 'C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe' --headless=new --disable-gpu `
  --hide-scrollbars --force-device-scale-factor=2 --window-size=1680,1050 `
  --virtual-time-budget=9000 --screenshot=build\fig3_4.png `
  'file:///D:/RISC_V_CPU_2026/release/evidence/logic_analyzer_board_85m/uart/uart_00.html'
```

它截的是真实采集数据的界面，不是摆拍；`uart_00.html` 本身由 `release/evidence/.../uart/summary.json` 与 `uart_00.log` 生成。

### 2.2 待绘制

无。全部完成。

### 2.2.0 已裁决的口径问题（2026-10-27）

| 项 | 结论 | 依据 |
|---|---|---|
| 交付位流 LUT / FF | **4,995 / 3,907**（原登记 4,479 / 3,610 为 10-10 旧位流） | `fpga/logic_analyzer_85m/flow.log` 布局布线后资源表 |
| 交付位流 WNS / WHS | **+0.577 ns / +0.308 ns**（原登记 +0.588 / +0.310） | `report_timing/mes50hp_logic_analyzer_pll_top.rtr` Slack |
| 交付位流估算 Fmax | **89.3841 MHz**（原登记 89.4721） | 1000/(11.7647−0.577) |
| 位流身份 | 三处副本 SHA 均为 `C017ED10…FA4F`，已重下到板复核 | `scripts/program_board.ps1 -Config la85` → `PROGRAM PASS`、done bit=1 |

更正已同步进 `release/evidence/claims_map.md` §1 与正文表 1-1。**UART 模式样本数（登记 240，实测 207）仍待确认**，图 3-8 与正文按实测 207 写。

### 2.2.1 数据图的复现方式

四张数据图不是手画的，由 `src/gen_data_figures.py` 从证据文件读数值、算几何、生成 `.drawio`：

```powershell
& 'D:\Python313\python.exe' docs\figures\src\gen_data_figures.py
```

| 图 | 数据源 |
|---|---|
| 图 3-5 | `release/evidence/automated_metrics.json` → `coremark_predictor_on` / `_off` |
| 图 3-6 | `docs/coremark_cpi_analysis.md` §8.1（rv32im，1 次迭代，-O2） |
| 图 3-7 | `release/evidence/claims_map.md` §3.1～§3.4 |
| 图 3-8 | `release/evidence/logic_analyzer_board_85m/<模式>/summary.json` |
| 图 3-9 | `release/evidence/claims_map.md` §1／§2／§3／§4／§5 + `release/evidence/automated_metrics.json`（由 `src/gen_data_table.py` 生成，五分区：处理器与交付位流 / CoreMark 实板 / 分支预测 Before-After / 逻辑分析仪 / 止损） |
| 图 3-10 | 同图 3-9 的同一份数据，改为 4×3 指标卡 + 止损条排版（宽而短，供正文插图与幻灯片使用）；同一脚本 `src/gen_data_table.py` 生成，与图 3-9 数字必须逐项一致 |
| 图 3-11 | `docs/trap_contract.md`（M-01…M-24）、`docs/demo_runbook.md`（板级中断与止损表）、`release/evidence/claims_map.md`、`release/evidence/automated_metrics.json`（左栏基础任务 6 项全完成；右栏进阶任务 3 项完成 / 2 项止损关闭，并附进阶路线与范围边界） |

不依赖 matplotlib：本机 Python 未安装，为避免改动用户环境，脚本只做坐标计算，渲染仍交给 draw.io，字体与配色和正文其它插图一致。
| 图 2-6 | 译码、冒险与前递流程图 | 2.3.2 | 译码 → 源寄存器冲突检测 → 停顿/前递选择 |
| 图 2-7 | 执行与乘除流程图 | 2.3.2 | ALU 选择 → 分支判定 → M 扩展多周期迭代 |
| 图 2-8 | 访存与异常提交流程图 | 2.3.2 | 地址计算 → 事务握手 → 退休判定 → 异常登记与冲刷 |
| 图 2-9 | 采集引擎与 MMIO 流程图 | 2.3.2 | 命令解析 → 触发判定 → 采样写 BRAM → 回读打包 |
| 图 2-10 | PC 端采集与解析流程图 | 2.3.2 | 串口读 → 报文校验 → 波形重建 → 读数计算 → 显示导出 |
| 图 3-4 | 上位机界面截图 | 3.2.3 | 运行工具截屏 |
| 图 3-5 | CoreMark Predictor 前后对比 | 3.3 | 数据图 |
| 图 3-6 | CPI 分解 | 3.3 | 数据图 |
| 图 3-7 | 工作频率与分数、时序余量 | 3.3 | 数据图 |
| 图 3-8 | 五模式采集结果 | 3.3 | 数据图 |

### 2.3 实拍（已完成，见 `docs/design_document.md` 附录 B）

| 图号 | 文件 | 状态 |
|---|---|---|
| 图 3-1 | `fig3_1_board_front_crop.jpg` | 定稿 |
| 图 3-2 | `fig3_2_board_oblique_crop.jpg` | 定稿 |
| 图 3-3 | `fig3_3_board_circuit_crop.jpg` | 定稿 |

## 3. 导出命令

```powershell
$exe = 'D:\.xinstall\draw.io\draw.io.exe'
& $exe -x -f svg --no-sandbox -o build\fig2_2.svg src\fig2_2_hardware_overview.drawio
& $exe -x -f png --no-sandbox -s 3 -b 20 -o build\fig2_2_hi.png src\fig2_2_hardware_overview.drawio
```

`s` 为缩放倍数，`b` 为外留白像素。`-s 3` 导出的 PNG 在 A4 版心 15.9 cm 宽插入时约 800 DPI 以上，远超印刷需求。
