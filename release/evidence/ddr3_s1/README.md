# S1（DDR3 打通）板级复核证据 — 2026-10-24

> 平台：MES50HP `PGL50H-6IFBG484`　串口：COM11 @ 115200 8N1
> 位流：`fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit`
> SHA-256：`FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76`
> （与 `fpga/ddr3_smoke/README.md` §5 记录的一致，未重打）

## 为什么有这个目录

`docs/handoff_next.md` §3.3 的 S1 小节长期挂着一句 **"⛔ 停在下载之前"** 的历史告示，
而 `fpga/ddr3_smoke/README.md` §5 记录的是 **"S1 DDR3 SMOKE BOARD PASS"**。
两份文档互相矛盾，任何人照着前者读都会以为 S1 没做完（本次复核就是这么被误导的）。
处置：在 §3.3 顶部补了"✅ 已完成，下列 ⛔ 是历史记录"的说明，并用**今天的实测**留一份带日期的证据。

## 实测（2026-10-24）

```powershell
scripts\program_board.ps1 -Config ddr3          # PROGRAM PASS，done bit = 1
python python\ddr3_smoke_board.py --port COM11 --seconds 12
```

```
0x80 = 0x00011110  pll_lock=0 dll_lock=1 ddr_init_done=1 err_flag=0
心跳计数 155 次，翻转 16 次（12 s 采样）
0x8B = err_cnt=0 main_state=3 wr_state=0 rd_state=2（15 次采样）

[PASS] DLL 锁定
[PASS] DDR3 初始化完成
[PASS] 心跳在翻转（控制器在跑）
[PASS] 无校验错误标志 err_flag_led
[PASS] BIST 错误计数全程为 0
[PASS] BIST 状态机在推进
[NOTE] pll_lock 状态位恒为 0（已知偏差，见下）

S1 DDR3 SMOKE BOARD PASS
```

原始输出：`ddr3_smoke_board_20261024.log`（本目录）。

## 已知偏差（照实抄，别抹）

状态寄存器 `0x80` 的 `pll_lock` 位（bit0）**恒为 0**，但同一份采样里
`dll_lock=1`、`ddr_init_done=1`、BIST 正常循环、`err_cnt=0`——这些都需要稳定的 PLL 时钟，
而且板上 LED1 实测常亮。⇒ 判定**该状态位本身不可信**（极性/接线），不是"PLL 没锁"。
验收脚本把它列为 NOTE 而不是 FAIL。

## 这个证据**不**证明什么

`test_ddr` 例程只做 BIST 与状态寄存器，**没有吞吐量/延迟测量**，
也**没有把 DDR3 接成 Core 的真实后端**。所以：

- 已证明：**DDR3 控制器在本板真正工作**（初始化、训练、读写循环、零错误）。
- 未证明：DDR3 的读/写带宽、单笔延迟，以及它作为 CPU 存储后端时的实际收益。
  这三个数字是 S2（行式突发）与 S3/S4（Cache）Before/After 的分母，必须另外测。
