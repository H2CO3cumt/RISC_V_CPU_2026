# trace85 组合采集证据：波形 + 指令流**同一次运行**（0xAB）

> 采集时间：2026-10-24　平台：MES50HP `PGL50H-6IFBG484`　串口：COM11 @ 115200
> 位流：`fpga/trace85/generate_bitstream/mes50hp_trace_pll_top.sbit`
> SHA-256：`2148CD6F009FCED49D65800B76E4BBB33627C9872186A8E4892776F80A62B5F5`
> PDS：`All Constraints Met`（85 MHz，WNS +361 ps / WHS +186 ps，DRM 44/134）

## 这一枪解决的是什么

tr85 位流里本来就有两部分：**8 通道逻辑分析仪**（`logic_analyzer_mmio`，8 根探针
接 Core 的握手/停顿/冲刷/提交）和**提交级 trace**（`core_trace_mmio`，每条退休指令）。
过去它们是两条命令、两次运行，所以"波形"和"指令流"永远对不到一起。

`0xAB` 把它们塞进**同一次运行**（固件 `trace_and_wave`）：

1. 先 arm trace（窗口从下一条退休指令开始，于是 LA 的 arm 指令本身也在 trace 里）；
2. 再 arm LA：**Core 探针源**、`div=0`（每拍一个样本）、触发 = 退休脉冲上升沿；
3. 跑与 `0xAA` phase 0 完全相同的那段处理循环；
4. 等 LA 采满 512 拍（这段自旋也在 trace 里，保证波形窗口**整段**被 trace 覆盖）；
5. 最后才 stop trace。

一次回包里先给波形块（`LA RAW count=… trigger=… window=… div=…` + 每样本 8 位十六进制），
再给指令流块（`TRACE RAW / TRACE MARK / TRACE TEXT`，字段与 `0xAA` 逐字段一致）。

## 对齐怎么算、怎么证

| 步 | 做法 |
|---|---|
| 锚点 | 在 trace 里找 `LA CONTROL = 1` 那条 store（`0x1000_2100`）——它就是"波形开始采样"的位置 |
| 拍号 | 波形里 **bit7（退休脉冲）** 的个数 = 这段窗口里退休了多少条指令，于是窗口覆盖记录 `[offset, offset+C)` |
| **交叉校验** | 波形里 **bit3&bit4（`d_req_valid & d_req_ready`）** 的拍数，必须等于上面区间里 **load+store 的条数**。两条来源完全独立：一条来自 Core 的握手线，一条来自提交记录 |

本枪实测：

```
ALIGN offset=1 anchor=1 delta=0 tied=[0, 2] cycles=512 retire=316 dv=97 rec=97 mismatch=0
```

- 512 拍窗口里数到 **316 个退休脉冲**（窗口 IPC ≈ 0.62），覆盖记录 **#1..#316**；
- 波形里 **97 个数据访问脉冲**，区间内 **97 条访存指令**，**差 0**；
- 候选偏移 `[0, 2]` 同样吻合（处理循环是周期性的）⇒ 页面与本文**如实标注对齐精度 ±1 条记录**，
  不假装唯一。

判据 **21/21 PASS**（15 条来自 `trace_board` 的 phase 0 判据 + 6 条来自 `judge_wave`）。

## 产物

| 文件 | 内容 |
|---|---|
| `trace_wave.log` | UART 原始回包（未加工，19 530 字节） |
| `trace_wave.json` | 判据逐条 + 对齐参数（offset/anchor/tied/mismatch）+ 摘要 |
| `trace_wave.html` | 单页可视化（与 `0xAA` 共用同一份页面模板） |

三条产物由**同一条命令**产生：`python python\trace_board.py`（界面里是第 2 页的
「波形+指令」按钮），判据与页面标注同源。

## 复现

```powershell
scripts\run_trace85_pds.ps1                       # 位流（All Constraints Met）
scripts\program_board.ps1 -Config tr85            # 下载
python python\trace_ui_board_check.py --port COM11 --text hello,rv --phase 0   # 界面路径
python -m unittest python.tests.test_trace_view   # 对齐算法的单测（含反例）
scripts\run_core_trace_soc_tb.ps1                 # 端到端仿真：0xAA 两场景 + 0xAB 一场景
```

## 边界（必须原样进材料）

- **这是提交级 + 每拍 的关联，不是"实时"**：一枪仍然要等收尾后上传（132 位/条 vs 115200）。
- **对齐精度 ±1 条记录**（本枪 `tied=[0,2]`）：ARM 写自己退休的那一拍既是"第 0 个样本"
  也可以是"下一个样本"的边界，两者只差一条记录；交叉校验能证伪错误的偏移，
  但在周期性负载下不能唯一确定 ±1。
- 波形窗口只有 512（或 1024）拍，覆盖的是 trace 窗口的**一段**，不是全部 323 条。
- 探针位序固定为 `{retire, flush, stall, d_ready, d_valid, i_rsp_valid, i_req_ready, i_req_valid}`
  （与 `fpga/trace85/rtl/mes50hp_trace_top.v` 的位拼接逐位一致），改一位就会让对齐与判据同时失效。
