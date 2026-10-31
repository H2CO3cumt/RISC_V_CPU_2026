# PDS 2024.2-SP2 与 ModelSim 2020.4 联合仿真

本文件记录本机 PDS（紫光同创 Fabric Compiler）与 ModelSim 联仿的配置方式、使用方法、
已知缺陷与排查方法。本配置只涉及仿真入口，**不改动任何 RTL，也不改变任何成绩数字**。

## 1. 结论（一句话）

在 PDS 里打开本仓库的 PDS 工程，点一次 **Behavior Simulation**，PDS 会自动调用 ModelSim
编译并运行 `tb/tb_msim_logic_analyzer_top.v`，随后 **ModelSim 的波形窗口自动打开并停在自检断点**，
不需要用户做任何手工设置。

## 2. 环境

| 项目 | 值 |
|---|---|
| PDS | `D:\Pango\PDS_2024.2-SP2`（2024.2-SP2-EN，build 208883） |
| ModelSim | `D:\modeltech64_2020.4`（ModelSim SE-64 2020.4，可执行文件在 `win64\`） |
| ModelSim 许可证 | `LM_LICENSE_FILE = D:\modeltech64_2020.4\win64\LICENSE.TXT`（已验证 `vsim -c` 可正常启动） |
| Pango 编译仿真库位置 | `D:\Pango\pango_sim_libraries`（本设计不使用 Pango 原语，该目录目前为空占位） |

> 注意：本机另有一份 `C:\modeltech64_10.1c`（10.1c）。联仿统一指向 **2020.4**，
> 即用户最新安装的那一份。

## 3. 已配置的工程

| 工程 | Testbench | 状态 |
|---|---|---|
| `fpga/logic_analyzer/logic_analyzer_generated.pds` | `../../tb/tb_msim_logic_analyzer_top.v` | 连续两次运行 ALL PASS |
| `release/final_submission/MES50HP_RISCV_Logic_Analyzer.pds` | `tb/tb_msim_logic_analyzer_top.v` | ALL PASS |

两个工程的 `.pds` 中 `(_widget wgt_simulation …)` 都被写成了：

```lisp
(_widget wgt_simulation
    (_option target (_string "ModelSim Simulator"))
    (_option top_module (_string "tb_msim_logic_analyzer_top"))
    (_option top_library (_string "work"))
    (_option top_architecture (_string ""))
    (_option compiled_lib_location (_string ".../pango_sim_libraries"))
    (_option sim_exe_dir (_string ".../modeltech64_2020.4/win64"))
    (_input
        (_file "<测试平台路径>"
            (_option is_top_spec (_boolean TRUE))
            (_format verilog)
            (_timespec "...")
            (_library "work")
        )
    )
)
```

并把 `_project` 里的 `is_user_specify_sim_top` 置为 `1`。

`sim_exe_dir` / `compiled_lib_location` 在 PDS 首次运行后会被自动改写成**相对工程目录**的形式
（例如 `../../../modeltech64_2020.4/win64`）。这是 PDS 的正常行为，窗口点过一次之后不必再动。

## 4. 使用方法

1. PDS 打开 `release/final_submission/MES50HP_RISCV_Logic_Analyzer.pds`（或开发工程 `fpga/logic_analyzer/...`）。
2. 在 Design Flow 的 Simulation 区点 **Behavior Simulation** 的 Run。
3. 等待约 1 分钟：PDS 会自动 `vlog` 全部设计源 + Testbench，再 `vsim` 装载并运行。
4. ModelSim 窗口打开，Wave 窗口已按 `add wave *` 加好信号，并 `zoom full` 整屏显示，
   仿真停在 testbench 的 `$stop` 断点（约 2.258 ms）。
5. 之后可以在 ModelSim 里自由加信号（例如 `add wave /tb_msim_logic_analyzer_top/dut/*`）、
   量时间、重新 `run -all`。

`run_behav_simulate.log` 里应看到：

```
[MSIM-TB] program image loaded from ../../rtl/program.mem (1024 words)
[MSIM-TB] 13-byte capture command sent at 2001330000
[MSIM-TB] PASS uart bytes=13
[MSIM-TB] PASS capture count=9 index=4
ALL MSIM LOGIC ANALYZER TOP TEST PASS
[MSIM-TB] simulation stopped at 2257970000 (waveform window stays open)
```

## 5. Testbench 说明

`tb/tb_msim_logic_analyzer_top.v`（交付包内为 `tb/tb_msim_logic_analyzer_top.v`）与
`tb/tb_logic_analyzer_board_top.v` 的命令序列完全一致（A5 帧），但为「在 PDS 里一键出波形」做了三处调整：

1. **真实时间轴**：时钟按板级 50 MHz（20 ns 周期）产生，UART 用真实 115200 分频（434 时钟/位），
   波形时间轴与实体板一致，不需要换算。一次完整验收约 2.26 ms。
2. **自己加载程序镜像**：PDS 会把仿真工作目录切到 `<工程>/sim/behav`，此时 RTL 里
   `$readmemh("rtl/program.mem")` 的相对路径必然找不到文件（ModelSim 会报一条 `vsim-7` 警告，
   存储体保持 X）。Testbench 因此不依赖它，而是用 `$fopen` + `$fscanf` 按候选路径列表
   （`../../rtl/program.mem`、`../../rtl/logic_analyzer_program.mem`、`rtl/...`）自己把镜像写进
   `dut.imem.mem` / `dut.dmem.mem`。因此无论 PDS 从哪个目录启动都能跑。
3. **用 `$stop` 而不是 `$finish` 收尾**：见下面第 6 节第 2 条。

自检内容与板级验收一致：UART 收到 13 字节、逻辑分析仪 `capture_count=9`、`trigger_index=4`、
`LED=0x5A`、`loopback_tx=0x01`、无 UART 帧错误。

## 6. 两个必须知道的工具行为（已绕开，勿回退）

### 6.1 PDS 的 `simulate_runtime` 回读有缺陷 —— `.pds` 里不能写它

PDS 2024.2-SP2 能把 `simulate_runtime` **写进** `.pds`，但**读不回来**：只要该键出现在
`.pds` 中，PDS 生成的 `sim/behav/run_behav_simulate.tcl` 就会出现乱码行（例如 `run x?UD?`），
ModelSim 报 `Invalid time value` 并且完全不推进仿真。换取值（`1us`/`2ms`/`1000`/`2000 ns`）
或换键名都不能解决；把该键删掉，PDS 回落到默认 `run 1000ns`（干净可用）。

**所以：两个 `.pds` 里都刻意不写 `simulate_runtime`。运行时长改由下面的钩子补齐。**

### 6.2 `%USERPROFILE%\modelsim.tcl` 全局钩子

`C:\Users\xwc\modelsim.tcl` 会被 ModelSim 在每次启动时自动 source。该文件只做三件事：

- 只在 PDS 生成的 `run_behav_simulate.tcl` / `run_post_syn_simulate.tcl` /
  `run_post_pnr_func_simulate.tcl` / `run_post_pnr_timing_simulate.tcl` 执行完之后，
  补一条 `run -all`，让仿真从默认的 1 µs 一直跑到 testbench 的断点；
- 补 `view wave` + `wave zoom full`，把波形窗口提到最前并整屏显示；
- 设置 `onfinish stop`：PDS 通过 `run_behav.bat` 启动 `modelsim.exe`，stdio 被重定向，
  此时 testbench 用 `$finish` 收尾会让 ModelSim **直接退出**，波形窗口看不到。
  配合 testbench 改用 `$stop`，窗口就能保持打开。

手工使用 ModelSim 不受影响：钩子只在匹配到 PDS 的仿真脚本名时才动作，其余情况 `do` 命令行为不变。

## 7. 相关文件改动清单

| 文件 | 改动 |
|---|---|
| `tb/tb_msim_logic_analyzer_top.v` | 新增：PDS/ModelSim 专用 Testbench |
| `fpga/logic_analyzer/logic_analyzer_generated.pds` | `wgt_simulation` 配置 ModelSim + 联仿源文件；`is_user_specify_sim_top=1` |
| `release/final_submission/MES50HP_RISCV_Logic_Analyzer.pds` | 同上（交付包副本） |
| `release/final_submission/tb/tb_msim_logic_analyzer_top.v` | 新增：交付包内的 Testbench 副本 |
| `release/final_submission/SHA256SUMS.txt` | `.pds` 哈希更新 + 新增 tb 条目 |
| `release/MES50HP_RISCV_Logic_Analyzer_Final.zip` | 按交付清单重建 |
| `release/SHA256SUMS.txt` | 同步上述脚本与 tb 的条目 |
| `scripts/export_final_submission.ps1` | 重新导出时把 tb 一并搬进交付包并改写 `.pds` 路径 |
| `scripts/audit_release_package.ps1` | 交付清单校验排除 `sim/`（PDS 仿真中间产物，与 `.lock`/`.log` 同类） |
| `.gitignore` | 忽略 `fpga/**/sim/` 与 `release/final_submission/sim/` |
| `C:\Users\xwc\modelsim.tcl` | 新增：ModelSim 全局启动钩子（仓库外） |

## 8. 已知限制

- 只配了 **Behavior Simulation**。Post-Synthesis / Post-PnR 仿真需要先用 PDS 走完综合与布局布线，
  且要 `compile_simlib` 编译 Pango 原语仿真库到 `D:\Pango\pango_sim_libraries`；本设计是纯通用
  Verilog（无 `GTP_*` 原语），行为仿真不需要这一步。
- 本仓库其余 PDS 工程（`fpga/pipeline_soc`、`fpga/coremark*`、`fpga/bram_smoke`、
  `fpga/logic_analyzer_80m`、`release/board_validation/projects/*` 等）**尚未**接入本联仿配置：
  它们的 Icarus Testbench 依赖仓库根目录作为工作目录、`$fatal` 收尾和各自的 `-D` 宏，
  直接搬进 PDS 需要在 tb 内部把程序镜像加载方式改成上面第 5 节第 2 条的做法。
  需要时按同样模式补即可（改 `wgt_simulation` + 加一个 PDS 版 tb）。
- 仿真中间产物写在 `<工程>/sim/behav/`。PDS 里执行 "Clean up simulation files" 会清掉它，
  下一次点仿真会重新生成，不影响正确性。

## 9. 排查

| 现象 | 处理 |
|---|---|
| 点 Run 后 PDS 报 `compiled_lib_location is not set` | 工程被外部改坏；检查 `wgt_simulation` 里该项是否是有效的绝对路径或正确的相对路径 |
| ModelSim 报 `Invalid time value` | `.pds` 里被写进了 `simulate_runtime`，删掉它 |
| 仿真只跑了 1 µs 就停住 | `C:\Users\xwc\modelsim.tcl` 钩子没生效（被删/改名），或该文件被 ModelSim 读成了别的编码 |
| 仿真跑完 ModelSim 直接关掉 | Testbench 用了 `$finish`，或钩子里的 `set onfinish stop` 没生效 |
| 日志有 `vsim-7 Failed to open readmem file "rtl/..."` 警告 | 正常：RTL 里 `$readmemh` 的相对路径在 `sim/behav` 下不成立，程序镜像由 Testbench 自己加载（紧接着的一行 `[MSIM-TB] program image loaded from …` 即为证据） |
