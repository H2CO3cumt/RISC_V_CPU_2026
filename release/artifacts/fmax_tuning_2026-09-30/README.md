# N4：把 Fmax 往上推（2026-09-30）

## 一句话结论

**交付工程报的 55.52 MHz 只是"时钟约束写成 20 ns"下的成绩，不是设计的频率能力。**

同一份 RTL、同一份配方、同一套约束（只改时钟周期数字），把约束收紧到 11.765 ns 后
PDS 依然 **All Constraints Met**，估算 Fmax 达到 **89.25 MHz**（WNS 仍有 +0.561 ns）。
即：**同一份 RTL 的实测频率能力 ≈ 89 MHz，比交付报告里的 55.52 MHz 高 60.7%。**

## Before / After（同一 RTL、同一配方，只有时钟约束不同）

| 约束周期 | 目标频率 | **估算 Fmax** | setup WNS | hold WHS | All Met | LUT | FF | DRM18K | 位流 |
|---:|---:|---:|---:|---:|---|---:|---:|---:|---|
| 20.000 ns | 50 MHz（**交付口径**） | **55.5216 MHz** | +1.989 | +0.315 | ✅ MET | 4536 | 3852 | 5.5 | `la_50m_constraint20ns.sbit` |
| 13.333 ns | 75 MHz | **80.0897 MHz** | +0.847 | +0.311 | ✅ MET | 4805 | 3858 | 5.5 | （见 `sweep_summary.csv`） |
| 12.500 ns | 80 MHz | **85.2370 MHz** | +0.768 | +0.310 | ✅ MET | 4814 | 3858 | 5.5 | `la_80m_constraint12p5ns.sbit` |
| **11.765 ns** | **85 MHz** | **89.2538 MHz** | +0.561 | +0.321 | ✅ **MET** | 4794 | 3858 | 5.5 | `la_85m_constraint11p765ns.sbit` |

**代价**：LUT 4536 → 4794（+5.7%）、FF 3852 → 3858（+0.16%）；DRM 不变。
**收益**：估算 Fmax 55.52 → 89.25 MHz（**+60.7%**）。

## 为什么这是"纯优化"而不是"换了个设计"

- **RTL 一个字都没改**。扫描用的是 `rtl/` 的**快照**，快照哈希见 `rtl_sha256.txt`：
  `pipeline_cpu.v = B58496706686E37BBA09E01861F1C7FE2AED8A5765C0F277E1F0DF5B91B071C2`
  —— 与工作区当前 `rtl/pipeline_cpu.v` **逐字节一致**。
- **功能语义不变**：只是让 PDS 按更紧的目标去布局布线。位流在板上仍以 50 MHz 运行。
- **同口径可比**：隔离扫描在 20 ns 约束下复现出的
  `est 55.5216 / WNS 1.989 / LUT 4536 / FF 3852`，与交付证据
  `release/evidence/automated_metrics.json` 的 `final` 组**完全相同** ⇒
  说明这套隔离工程忠实复现了交付配置，四组数字可以直接横向比较。

## 复现命令

```powershell
# 隔离扫描：RTL/配方/约束都在临时目录里各建一份，绝不污染 fpga/logic_analyzer 的正式产物
scripts\run_fmax_sweep_rtl.ps1 -Tag la_now `
  -Periods '20.000,13.333,12.500,11.765' `
  -RecipeSource 'D:\RISC_V_CPU_2026\fpga\logic_analyzer\pds_recipe.tcl' `
  -FdcSource    'D:\RISC_V_CPU_2026\fpga\logic_analyzer\constraints\mes50hp_logic_analyzer.fdc' `
  -FdcName      'mes50hp_logic_analyzer.fdc' `
  -MemorySource 'D:\RISC_V_CPU_2026\fpga\logic_analyzer\rtl'
# 汇总在 tmp/fmax_sweep/la_now_sweep_summary.csv，工程在 tmp/fmax_sweep/la_now_proj/f<freq>/
```

**本轮修掉的一个扫描脚本缺陷**：`run_fmax_sweep_rtl.ps1` 原来把写出的 `.fdc` 文件名
**写死成 `mes50hp_coremark.fdc`**，于是用它扫描 `logic_analyzer` 的配方时，
配方里 `add_constraint` 指向的名字对不上 ⇒ **约束根本没被加载**，扫描结果全是"无约束"的。
现已加 `-FdcName` 参数（默认仍是 coremark 的名字，向后兼容）。

## 如实边界（不得含糊）

1. **交付位流没有被替换**。`fpga/logic_analyzer/generate_bitstream/…sbit`
   仍是 `BCAE040A3B96652BB4B73907FFA03178C05453C0E9CD07E5697E401845FDD184`
   （与 `release/final_submission/bitstream/` 和 `release/artifacts/` 三处一致），
   **实板证据因此仍然有效**。
2. **本目录的 `.sbit` 已在 2026-09-30 做板级复验**（`la_85m_constraint11p765ns.sbit`）：
   `PROGRAM PASS` + `The done bit is 1`，J8 四模式 **80/80 PASS**，
   且四个模式的采集结果与交付位流**逐字节相同** ⇒ **收紧约束只改布局布线、不改功能**。
   证据：`release/evidence/fmax_candidate_board/`。
   **但这不等于"板上跑到 89.25 MHz"** —— 板载晶振固定 50 MHz，候选位流在板上仍跑 50 MHz。
   若要把它作为**交付位流**，还差：实板 CoreMark（本候选是逻辑分析仪顶层，不跑 CoreMark）+
   重跑 `export_final_submission.ps1` / `audit_release_package.ps1` + 更新全部哈希登记点。
3. 本目录三份 `.sbit` 的哈希与交付位流**不同**，原因是**构建目录不同**（路径参与布局种子），
   不是设计不同 —— 20 ns 那组的**指标**与交付完全一致即可佐证。
4. 89.25 MHz 是**PDS 时序分析的估算值**，不是实板跑到的频率；
   板上系统时钟固定 50 MHz（80 MHz 需用 PLL 构建，见 `fpga/logic_analyzer_80m`）。
   → **2026-09-30 已按这条路补上板级实测点**：新建 `fpga/logic_analyzer_85m` 与
   `fpga/coremark_85m`，把 `STATIC_RATIOF` 16 → **17**（VCO 850 MHz）得到 **85.000 MHz**，
   板级实测 **CoreMark Score 79.587 / CoreMark-MHz 0.936 / CRC PASS** 与
   **逻辑分析仪四模式 80/80**。
   即：**板级实测最高工作频率 = 85.000 MHz；89.2538 MHz 仍是估算**。详见
   **`release/evidence/board_85m/README.md`**。
5. 90 MHz 及以上**没有测**：本轮的扫描点最高到 85 MHz（11.765 ns）。
   前序扫描（2026-09-17，老 RTL）在 90 MHz 上出现 WNS −0.059 ~ −0.374 的违例。

## 文件清单

| 文件 | 内容 |
|---|---|
| `la_50m_constraint20ns.sbit` / `_timing.rtr` | 20 ns 约束（交付口径）的复现构建 |
| `la_80m_constraint12p5ns.sbit` / `_timing.rtr` | 12.5 ns（80 MHz）约束构建，est 85.24 MHz |
| `la_85m_constraint11p765ns.sbit` / `_timing.rtr` | 11.765 ns（85 MHz）约束构建，est **89.25 MHz**（本轮最优） |
| `sweep_summary.csv` | 四个频点的完整时序/资源汇总（脚本自动提取） |
| `rtl_sha256.txt` | 扫描所用 RTL 快照的逐文件 SHA-256（证明是当前 RTL） |
