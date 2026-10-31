# Fmax 上界实测：最大能跑到多少（2026-09-30）

> ⚠️ **2026-09-30 后续更新：交付配置已切换。** 本文写于切换之前，文中"交付位流 = `BCAE040A…`（50 MHz）"
> 的表述**已过期**。现在的交付主位流是 **85 MHz PLL 版**（`C017ED10…` 重建批次，
> 工程 `fpga/logic_analyzer_85m`；本文当时写的是 `F7DFD321…`），
> 50 MHz 版（`BCAE040A…` → 重建后 `8102634A…`）改为**已验证备用位流**随包提供。
> 本文其余内容（波形、对比、上界结论）**不受影响**，因为那些结论与"哪一颗是交付位流"无关。

> ➕ **2026-10-14 追加：RV32IM（M 扩展）在 85 MHz 上也收敛并上板了。**
> 新工程 `fpga/coremark_im_85m`（源文件取自本表的 CM 85m，只把镜像换成 `-march=rv32im`，4000 迭代）：
> `All Constraints Met`，85.0000 MHz 请求 / **86.8456 MHz** 估算，setup WNS **+0.250 ns**，
> **4198 LUT / 3361 FF**；实体板 **Score 193.192、CoreMark/MHz 2.272、20.704 s、官方 CRC PASS**。
> 位流 `EE8B65360B0B07189C66460D813A6CC990FE87BE156AEA5BC7779B5D3C68D6F1`。
> **同源对照点**：同一份源码重新构建的 rv32i 位流 `fpga/coremark_85m_r`（`EC71AFDD…`）
> 资源/时序**逐项相同**（4198 LUT / 3361 FF / WNS +0.250 ns），实体板 Score **79.587**、
> `ticks = 2,670,014,377` 与 09-30 的归档 rv32i 位流**逐位相同**。
> 结论：**M 扩展不降低可用的最高工作频率，也不扰动 RV32I**——rv32i 的 85/90 MHz 结论对带 M 的配置同样成立
> （85 MHz 已由这两点直接证明；90 MHz 未对带 M 的 CoreMark 配置复测）。
> 明细见 `release/evidence/claims_map.md` §3.1c / §3.1d。
>
> ⚠️ 另需注意本表下方"50 MHz 工程估算 Fmax ≈55–58 MHz"那类数字是**目标频率造成的假象**：
> 50 MHz 目标下 PDS 的最差路径落在 `imem/RSTA`、`ifid_inst/RS` 这类**复位端**，与 85 MHz 下
> 真正的关键路径（`RF → fetch_pc/CE`）不是同一条，不能拿来当设计上界。

> 回答"**最大 Fmax 能是多少**"。做法是把 PLL 逐级往上推、每一级都**真的上板测**，
> 而不是只看 PDS 估算。结论分两个口径，因为**两个配置的上界不一样**。

## 1. 一句话结论

| 问的是什么 | 答案 | 依据 |
|---|---|---|
| **PDS 时序能收敛到多少** | **≈ 90.6 MHz**（CoreMark 配置）/ **≈ 91.6 MHz**（LA 配置） | 90 MHz 收敛、95 MHz 违例 |
| **CPU 核心 + 最小 SoC 板级能跑到多少** | **90 MHz**（CoreMark 跑完、CRC 正确） | `cm90` 板上实测 |
| **完整逻辑分析仪应用板级能跑到多少** | **85 MHz**（90 MHz 下 SPI 模式挂死） | `la90` 板上实测 |
| **交付配置的诚实口径** | **85 MHz**（交付的是逻辑分析仪应用） | 同上 |

**95 MHz 及以上：PDS 时序已经不过（WNS −0.391 ns），因此没有上板。**

## 2. 全部频点的完整数据

| 配置 | PDS 目标 | PDS 结果 | Slack | 估算 Fmax | **板级实测** |
|---|---|---|---|---|---|
| LA 80m | 80 MHz | All Constraints Met | +0.789 | 85.3898 MHz | 四模式 80/80 ✓ |
| LA 85m | 85 MHz | All Constraints Met | +0.663 | 90.0766 MHz | 四模式 80/80 ✓ |
| **LA 90m** | 90 MHz | All Constraints Met | **+0.191** | 91.5742 MHz | static/counter/uart ✓，**spi 挂死** ✗ |
| CM 85m | 85 MHz | All Constraints Met | +0.435 | 88.2637 MHz | CoreMark **79.587** ✓ |
| **CM 90m** | 90 MHz | All Constraints Met | **+0.072** | 90.5870 MHz | CoreMark **84.269** ✓ |
| **CM 95m** | 95 MHz | **Some Constraints Violated** | **−0.391** | 91.5975 MHz | **未上板**（时序不过） |

**独立交叉验证（PDS 约束扫描）**：用隔离工程扫 CoreMark 配置——
`11.5 ns → MET (+0.308)`、`11.0 ns → VIOLATED (−0.198, 134 个失败端点)`。
两条独立路径都指向"关键路径 ≈ 11.0~11.2 ns，即 **90~91 MHz**"。

## 3. PLL 频率阶梯（为什么测的是 80/85/90/95）

板载晶振固定 50 MHz，`PFD = 50/IDIV = 50 MHz`，`VCO = 50 × FDIV`（须落在 **600~1250 MHz**），
`输出 = VCO / ODIV0`。取 `ODIV0 = 10` 就得到 **5 MHz 整数步进**：

| FDIV | ODIV0 | VCO | 输出 |
|---|---|---|---|
| 16 | 10 | 800 MHz | 80.000 MHz |
| 17 | 10 | 850 MHz | 85.000 MHz |
| **18** | 10 | **900 MHz** | **90.000 MHz** |
| **19** | 10 | **950 MHz** | **95.000 MHz**（时序不过） |
| 20 | 10 | 1000 MHz | 100.000 MHz |

（还有更细的非 5 MHz 步进，例如 `16/9 = 88.889`、`20/11 = 90.909`。
但 90 MHz 的 CoreMark 已经只剩 **+0.072 ns** 余量 ⇒ 关键路径 ≈ 11.039 ns ⇒ **90.59 MHz 就是上限**，
再往上加没有任何余地，所以没有继续试。）

## 4. 90 MHz 下的真实失败点（重要，别误读）

90 MHz 的**逻辑分析仪配置 PDS 时序是过的（+0.191 ns）**，但板上按模式表现不同：

| 模式 | 90 MHz 结果 |
|---|---|
| static | ✓（132 字节，`LA_DONE`） |
| counter | ✓ |
| uart | ✓（2255 字节，`LA_DONE`） |
| **spi** | **✗ 收到 0 字节** —— 发出 SPI 配置包后固件**永久卡死**，之后再发 static 也无响应，必须重下位流才能恢复 |

**可复现**：重下位流后立刻**只跑 spi** 仍失败。所以不是"跑久了发热"这类偶发。

**为什么只挂 SPI**：spi 模式的采集配置是 `pattern_div=3, sample_div=0` —— `sample_div=0` 意味着
**采集引擎每拍采样（90 MS/s）**，是四种模式里最吃时序的一条路径。它在 90 MHz 上余量不足，
在 85 MHz 上没问题。这与"PDS 报 +0.191 ns"并不矛盾：**PDS 是标称角的名义分析，
板上还有温度/电压/时钟抖动的裕度损耗**，0.191 ns 的余量不足以覆盖。

⇒ **按项目一贯的止损纪律：90 MHz 的 LA 配置判为不达标，逻辑分析仪应用的板级上界记为 85 MHz。**

## 5. 附带的强证据：三/四频点 CoreMark 自洽

| 频率 | Score | CoreMark/MHz | ticks |
|---|---|---|---|
| 50 MHz | 46.816 | **0.936** | 1,068,006,999 |
| 80 MHz | 74.905 | **0.936** | 2,670,014,377 |
| 85 MHz | 79.587 | **0.936** | 2,670,014,377 |
| **90 MHz** | **84.269** | **0.936** | 2,670,014,377 |

折算逐个对上：`84.269 × 85/90 = 79.587`、`× 80/90 = 74.905`、`× 50/90 = 46.816`。
**四个独立频点、四个独立位流，分数严格成比例，CoreMark/MHz 恒为 0.936。**

## 6. 产物与复现

| 位流 | SHA-256 | 上板结果 |
|---|---|---|
| `fpga/logic_analyzer_90m/…pll_top.sbit` | `0315374E5FA60F49D28BA213D185D4EE9BE7E5B3CCAEE1573DA2EE6414038D48` | SPI 挂死 |
| `fpga/coremark_90m/…pll_top.sbit` | `664CD28CFFDB166FAFDB350B1BD01A839C3FDBDA239351361673CE3876A59CEC` | CoreMark 84.269 ✓ |
| `fpga/coremark_95m/…pll_top.sbit` | `2C060A1FBE3F06A409DE79D04E76562C28F6CEA6C301419AEB15E181C9EC219E` | 未测（时序违例） |

```powershell
# 构建（PDS）
scripts\run_logic_analyzer_90m_pds.ps1
scripts\run_coremark_90m_pds.ps1
scripts\run_coremark_95m_pds.ps1
# 上板
scripts\program_board.ps1 -Config la90      # 或 -BitstreamPath <任意 .sbit>
scripts\run_logic_analyzer_board.ps1 -Port COM11 -RunsPerMode 20
scripts\run_coremark_board.ps1 -Port COM11
```

## 7. 如实边界

1. **95 MHz 没有上板**，因为 PDS 已报 `Some Constraints Violated`（−0.391 ns）。
   时序不过的位流上板跑出来的"结果"没有意义，也违反项目纪律。
2. **90 MHz 的 CoreMark 通过**只能说明"CPU 核心 + 最小 SoC"能跑 90 MHz，
   **不能**说明整个逻辑分析仪应用能跑 90 MHz（事实相反）。
3. `95 MHz` 的 PDS 估算 Fmax 是 **91.5975 MHz**，比 90 MHz 那版的 90.5870 MHz 还高 ——
   这是布局布线的随机性，**不要**把 91.5975 当成"能跑 91.6 MHz"。
   真实上界以"**能 All Constraints Met 且板上功能正确**"为准。
4. 本轮**没有**做温度/电压拉偏（没有温箱、没有可调电源），
   所以上述上界是**常温常压**下的结论。
5. 90 MHz 的 LA 位流与 95 MHz 的 CM 位流都**不是**交付入口；
   **交付主位流是 85 MHz PLL 版（`F7DFD321…`）**，50 MHz 版（`BCAE040A…`）为已验证备用。

---

*本证据由 2026-09-30 上板实测建立（MES50HP / PGL50H-6IFBG484，PDS 2024.2-SP2）。*
*数字出处索引见 `release/evidence/claims_map.md`。*
