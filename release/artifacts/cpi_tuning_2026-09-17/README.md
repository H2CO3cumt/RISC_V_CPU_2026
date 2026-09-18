# CPI 优化专项归档（2026-09-17）

> 本轮唯一 RTL 改动：`rtl/pipeline_cpu.v` 取指满速交接（`if_arm`）+ Core 外取指存储器 ready 策略。
> 逐条说明见 `docs/rtl_changes.md` 改动 2；归因见 `docs/coremark_cpi_analysis.md`；定位过程见 `docs/debug_log.md`。
> **本目录是并存的新交付物，未替换 `release/final_submission/` 与 `release/artifacts/fmax_tuning_2026-09-17/` 里的既有清单。**

## RTL 指纹

| 文件 | SHA-256 前 16 |
|---|---|
| `rtl/pipeline_cpu.v`（改动前 → 改动后） | `8E8EB3A69B2EF45E` → `BD8BA8640C3B6A4D` |
| `rtl/perf_monitor.v`（未改） | `B9A41F8D23956422` |

## 位流（全部 `All Constraints Met`，全部实体板实测通过）

| 文件 | 工程 | 时序 | SHA-256 |
|---|---|---|---|
| `coremark_50m_cpi.sbit` | `fpga/task28_coremark` | WNS +2.349 ns | `3791D1E7D91D90AC70A9ABF30AF13883E10A7A44DF8698676F694AD936F909B2` |
| `coremark_80m_pll_cpi.sbit` | `fpga/task28_coremark_80m` | WNS +0.667 ns，估计 Fmax 84.51 MHz | `34BA88F53FD0FF9C5AE6CF806EC21E0ECE1271DA87876D35C226D36AADF18FDE` |
| `la_50m_cpi.sbit` | `fpga/task30_logic_analyzer` | WNS +2.812 ns | `17FD57D8F12FF4DCC8FC3A66D644561973E9D75AB9286F09D2F506F94BCDB092` |
| `la_80m_pll_cpi.sbit` | `fpga/task30_logic_analyzer_80m` | WNS +0.789 ns，估计 Fmax 85.39 MHz | `0388100A6D4714027E98ADCA17512FE9C64318870D3559AC15F123860A3E8E2E` |

## 实体板实测结果（Before → After）

| 配置 | Score | CoreMark/MHz | CPI | ticks | 秒数 | 官方 CRC |
|---|---:|---:|---:|---:|---:|---|
| CoreMark 50 MHz（Before，上一轮位流） | 29.559 | 591 | 2.3443 | 1,691,496,677 | 33.829 | 全过 `0xd340` |
| **CoreMark 50 MHz（After）** | **45.051** | **901** | **1.5388** | 1,109,848,679 | 22.196 | 全过 `0xd340` |
| CoreMark 80 MHz PLL（Before） | 47.295 | 591 | 2.3445 | 4,228,738,028 | 52.859 | 全过 `0x5275` |
| **CoreMark 80 MHz PLL（After）** | **72.081** | **901** | **1.5387** | 2,774,618,621 | 34.682 | 全过 `0x5275` |
| 逻辑分析仪 50 MHz | — | — | — | — | — | 80/80 回环 PASS |
| 逻辑分析仪 80 MHz PLL | — | — | — | — | — | 80/80 回环 PASS |

两次 CoreMark 运行均满足：四个官方 CRC 全过 + `Correct operation validated.` + 运行 ≥10 s。

## 证据文件

| 文件 | 内容 |
|---|---|
| `release/evidence/coremark_uart_cpi50m.log` / `coremark_board_cpi50m.json` | 50 MHz 实体板串口原文与解析结果 |
| `release/evidence/coremark_uart_cpi80m.log` / `coremark_board_cpi80m.json` | 80 MHz PLL 实体板串口原文与解析结果 |
| `release/evidence/logic_analyzer_board_cpi50m/` | 逻辑分析仪 50 MHz 四模式各 20 轮 |
| `release/evidence/logic_analyzer_board_cpi80m/` | 逻辑分析仪 80 MHz PLL 四模式各 20 轮 |
| `fpga/*/report_timing/*.rtr` | 四套工程的时序报告 |

## 复现命令

```powershell
# 1) 生成板级镜像（必须带 -PerfWindowAlign 1）
& '<pwsh7>' -NoProfile -File scripts\generate_coremark_fpga_memory.ps1 -Iterations 1000 -ClockHz 50000000 -AutoStart 0 -PerfWindowAlign 1
# 2) 综合布局布线（PDS）
cd fpga\task28_coremark; & 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file pds_recipe.tcl -project_name task28_generated
# 3) JTAG 下载 + 串口采集
Start-Process 'D:\Pango\PDS_2024.2-SP2\bin\cdt_js.exe' -ArgumentList '-work_dir','D:\RISC_V_CPU_2026\tmp','-port','65420'
& 'D:\Pango\PDS_2024.2-SP2\bin\cdt_cfg.exe' -file D:\RISC_V_CPU_2026\tmp\program_coremark_wa.tcl -work_dir D:\RISC_V_CPU_2026\tmp
D:\Python313\python.exe python\coremark_serial.py COM11 --clock-hz 50000000 --timeout 200 `
  --output release\evidence\coremark_uart_cpi50m.log --summary release\evidence\coremark_board_cpi50m.json
```
