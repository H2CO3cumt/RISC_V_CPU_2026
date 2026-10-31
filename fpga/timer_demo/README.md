# M-24 / N1：MES50HP 板级周期性定时器中断演示

本目录是**最小板级工程**，唯一的目的是把已经做完的高阶任务②（机器模式 CSR / 精确 Trap /
三根通用中断输入）从"仿真通过"升级为"实板可复现"，也就是 Trap 契约里 **M-24** 的板级那一半。

它不改动任何交付物：`rtl/pipeline_cpu.v` 的功能行为未动，`fpga/logic_analyzer` 的程序镜像与位流未动。

## 1. 演示出来的三件事

| # | 现象 | 怎么看 |
|---|---|---|
| 1 | **中断周期性发生** | LED0（板上 LED1，管脚 `B2`）每 `MTIMECMP_DELTA` 拍翻转一次。缺省 `12_500_000` 拍 → 每 0.25 s 翻转一次，**整周期 0.5 s** 闪烁，人眼可数、秒表可测 |
| 2 | **ISR 真的在跑** | 每次中断往串口写 **5 个字节**：`中断计数低 4 位（十六进制）` + `LED 值低 4 位` + `mtime[27:16] 的三位十六进制`。最后三位是**自计时**证据：mtime 是 50 MHz 硬件计数器，相邻两次之差 × 65536 就是中断周期（单位：拍），完全不依赖主机串口时钟 |
| 3 | **`mret` 回到了被打断的位置** | 主程序是一条自跳转；ISR 返回后仍停在原地，计数持续递增、LED 持续翻转 |

串口上先出现一个自检字符 `=`（证明程序跑到了初始化结束），之后稳态序列形如：

```
=101112131415161718191a1b1c1d1e1f1011...
```

> 注意：计数到 10..15 时打印出来的是 `:` `;` `<` `=` `>` `?`（十六进制 0..15 直接映射到 ASCII）。
> 所以看到标点不要当成乱码——那是**正常**的十六进制位，判据脚本按十六进制解析。

奇数位是连续递增的中断计数，偶数位是 LED 值。由于 ISR 每次只翻转 bit0、其余位保持 0，
LED 值只可能是 `0` 或 `1`，所以偶数位必然在 `0/1` 之间交替——**这本身就是"LED0 在按周期
翻转"的串口侧证据**，不必一直盯着板子。

## 2. 目录内容

| 文件 | 作用 |
|---|---|
| `rtl/mes50hp_timer_demo_top.v` | 板级顶层：Core + `soc_data_interconnect` + `timer_mmio` + `uart_mmio` + `gpio_mmio` + `perf_monitor` + IMEM/DMEM |
| `rtl/timer_demo_program_memory.v` | **生成物**：IMEM/DMEM（同一份 BRAM 镜像） |
| `rtl/timer_demo_program.mem` | **生成物**：1024 字的程序镜像（程序区之外填 `jal x0,0`） |
| `constraints/mes50hp_timer_demo.fdc` | 只约束实际使用的 10 个信号：`clk_50m=P20`、`uart0_rx=R8`、`uart0_tx=R9`、`led[7:0]=B2,A2,B3,A3,C5,A5,F7,F8` |
| `pds_recipe.tcl` | PDS 构建配方（含 `rtl/timer_mmio.v`） |

固件源码在 `software/timer_demo/`（`start.S` + `timer_demo_config.S` + `link.ld` + `Makefile`）。

## 3. 怎么构建、怎么跑

```powershell
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

# 3.1 只做仿真验收（两遍：零延迟 + 随机背压，各 15 条断言）
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board_top_tb.ps1

# 3.2 构建位流（会先用真实 delta 重新生成交付镜像，再综合/布局布线/时序/位流）
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_pds.ps1

# 3.3 下载 + 采集串口证据（同时请人眼确认 LED0 闪烁）
& $ps -NoProfile -ExecutionPolicy Bypass -File scripts\run_timer_demo_board.ps1 -Port COM11
```

已下载过位流时可以用 `-SkipProgram` 只重采证据。

## 4. 必须知道的坑（都是本轮实测踩出来的）

1. **`mtimecmp_hi` 必须先清零。** 它复位值是全 1（保证复位后不产生中断），只写低 32 位的
   话 `mtime < mtimecmp` 恒成立，中断永远不来。
2. **重装 `mtimecmp` 必须放在 ISR 最前面。** 本 ISR 要发 5 个 UART 字节；如果先发串口再重装，
   UART 忙的时候 CPU 会停在 TXDATA 那条 store 上等背压，重装被推迟到"上一个字节发完"，
   实测 `delta=20000` 时间隔变成 **24358**（多出的 4358 拍 ≈ 50 MHz/115200 的一个字节时间），
   "周期可预测"就名不副实了。放到最前面之后间隔是 `delta + 6` 拍且逐次完全相等。
3. **`-march=rv32i` 的汇编器不认 CSR 助记符。** 这条 march 不含 `zicsr`，`csrrw/csrrs/mret`
   会被拒绝（`extension 'zicsr' required`）。所以 `start.S` 里 CSR 指令写成 `.word <编码>`，
   每条编码都与已经逐项 PASS 的 `tb/data/timer_irq.mem`（M-14）逐位一致。
4. **字符表必须覆盖 0..15。** ISR 是拿"十六进制位"当下标查表的，表里少了 `'a'..'f'`
   就会越界读进程序区之外的填充字（`0x0000006F` = `jal x0,0`），串口上打印出 `'o'`——
   现象很像 UART 出错，其实是**表越界**。
5. **自计时字段不能太窄。** 取 `mtime[15:4]`（步长 16 拍）时模只有 65536 拍，
   而 delta = 12_500_000 拍，一个间隔会回绕 190 次，算出来的差值毫无意义。
   现在取 `mtime[27:16]`（步长 65536 拍，模 268M 拍）。

另外两条环境事实：本工程的 Testbench 必须用 **Icarus 12**（`D:\Tools\iverilog-v12`）；
PATH 里的 oss-cad-suite（Icarus 14）会在 `rtl/pipeline_cpu.v` 上报
"declaration after use" 而无法 elaborate，那不是 RTL 的问题。还有 **Icarus 12 会静默忽略
`-P <tb>.<param>=...`**，所以 Testbench 的 delta 用 `` `ifdef `` 宏覆盖而不是 `-P`。
（更完整的过程见 `docs/debug_log.md` 的 2026-09-29 条。）

## 5. 证据文件

| 文件 | 内容 |
|---|---|
| `release/evidence/timer_demo_board/timer_demo_board.json` | 判定结果：记录数、计数序列、LED 序列、自计时周期、墙钟量级 |
| `release/evidence/timer_demo_board/uart/uart_00.log` | 原始串口字节流 |
| `tmp/timer_demo/` | iverilog 两遍的完整输出 |
| `fpga/timer_demo/pds_timer_demo_build.log` | PDS 全流程日志（含 `All Constraints Met` 与资源占用） |

## 6. 已知限制与风险（如实记录）

1. **主机侧串口吞吐偏低，会丢字节**。实测 20 秒窗口只收到约 400 字节（≈ 48 条记录），
   而板上按 0.25 s 周期应发出约 96 条记录；同一窗口内主机墙钟估算因此偏大
   （378 ms vs 真实 250 ms）。**判据因此以自计时周期为准**（mtime 是硬件计数器），
   墙钟只做量级核对。丢字节会让之后的记录整体错位，解析器用"相位搜索 + 自计时判别式"
   把它们重新对齐（见 `python/timer_demo_serial.py` 的 `parse_runs`）；
   实测两次成功采集分别得到 43 / 48 条记录、38 / 43 个间隔，全部落在容差内。
2. **板上存在一个"约 85 秒后跑飞"的状态，根因未定位（已知风险，已做到可复现指纹）**。

   **指纹（2026-09-29 实测，按 5 秒一段连续观察 180 秒）**：

   | 时间（下载后） | 串口速率 | 内容 |
   |---|---|---|
   | t+0 … t+80 s | 稳定 **20.0 B/s**（5 字节 / 250 ms） | 正确记录 |
   | t+85 s 起 | 突变 **11571 B/s** 并保持 | 规律性错帧 |

   注意 11520 B/s 恰好是"115200 baud 下把持续低电平当成连续帧"的产物
   （115200/10 = 11520，实测 11571 差 0.4%），但解出来的字节**不是全 0**、
   而且带"计数在递增 + LED 位在 0/1 交替 + mtime 字段在快速变化"的规律结构，
   所以不是单纯的总线被拉低。

   **已排除的原因**：

   | 排除项 | 证据 |
   |---|---|
   | 主机侧串口/线缆 | 同一根线、同一个 115200 配置下，已交付的 `la50` 位流在 t+95 s 仍 **4/4 PASS**；`cm50` 能干净回出 `COREMARK_START` |
   | FPGA 配置丢失 | 异常期间用 `cdt_cfg` 的 `cfg_scan_chain` 读回 **done bit = 1**，配置没掉 |
   | 本设计用了 PLL/OSC/时钟分频 | PDS 报告里 `PLL 0 / OSC 0 / IOCKDIV 0`，只有 PDS 自动插入的一个 `GTP_CLKBUFG`；`.fdc` 里 `create_clock ... -period 20.000` 指向 P20，与交付工程逐字相同 |
   | 设计里的组合/时序逻辑跑飞 | 仿真（含随机背压）两遍全绿；异常后**重新下载位流必恢复**，且"下载后 49 秒内 4/4 PASS" |
   | 数据本就发得更多 | 稳定窗口内自计时中位周期恒为 **12_517_376 拍 = 250.348 ms**（26～27 个间隔），与 0.25 s 设计值一致 |

   **结论**：现象与**板上时钟频率在运行中发生变化**最相符（CPU 与 mtime 同步变快，
   所以串口速率与"记录变化速度"一起变快，而波特率量级仍对得上 ⇒ 不是单纯的波特率错配）。
   本工程无法在 RTL 里修它。

   **验收流程因此固定为**：`scripts\run_timer_demo_repeat.ps1` 先下载、再在窗口内连采
   （默认 4 次 × 12 秒，实测 4/4 PASS，全部 250.348 ms）。

   **下次接班请优先查清这一条**，建议顺序：
   1. 用示波器/频率计直接测 P20（板上 50 MHz 源）在 t+0 / t+90 s 的频率；
   2. 换一个 50 MHz 源（或换板）复测同一份位流；
   3. 若换板后仍复现，再比较 `timer_demo` 与 `la50` 的布放差异
      （`la50` 目前不复现，差异点可能就是触发条件，例如时钟网络的布放/负载）。
3. LED 闪烁本身靠人眼/视频确认，脚本只负责串口侧可自动判定的部分。
4. 本工程是**演示用**工程，不参与 `release/final_submission` 交付包，
   也不改变三个交付位流中的任何一个。
