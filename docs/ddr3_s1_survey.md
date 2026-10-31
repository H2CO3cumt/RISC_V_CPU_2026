# S1：DDR3 / HMIC 打通 —— 前置调研与硬件确认单

> 生成时间：2026-09-29（第 2 版：拿到 MES50HP 官方手册后**推翻了"厂商模板可直接用"这个假设**）。
> 对应 `docs/handoff_next.md` §3.3 的 **S1 闸门**（时间盒 2 个轮次）。
> 本文只记录**已核对过的事实**；未确认项一律标"待确认"，不得当成已知条件往下做
> （`AGENTS.md` §3 禁止臆测管脚）。

---

## 0. 最重要的一条：**厂商例程的 DDR3 管脚与本板对不上，不能直接用**

`ipsxb_hmic_s` 包里的 `50h_ddr3_fbg484_b3_x32.fdc` 名字看起来正好匹配
（50h + FBG484 + x32），但把它与 **MES50HP 官方硬件手册**（《盘古 50K 开发板（PGL50H）
硬件指导手册》表 2-4「PGL50H 与 DDR3 连接引脚分配表」）逐脚比对后：

| 项 | 结果 |
|---|---|
| DDR3 信号总数 | 手册 72 条（含 `ddr3_ck_n` / `ddr3_cke`）／模板 71 条 |
| **管脚一致的** | **4 条** |
| **管脚不一致的** | **65 条** |
| 典型错位 | 模板 `mem_ck=F3`，而手册 **`F3 = ddr3_addr[3]`**；模板 `mem_cs_n=C1`，手册 `C1 = ddr3_reset_n`；模板 `mem_ba[0]=G6`，手册 `G6 = ddr3_cs_n` |
| 用户现场核对 | 用户查手册确认：**F14 不是板上的 50 MHz 时钟**（手册标为网口 1 的 RX_CLK），**Y11 是 J8 扩展口引脚**；板载 50 MHz 晶振接 **P20** |

**结论**：`50h_ddr3_fbg484_b3_x32.fdc` 是给**另一块板**（或另一版 PCB）用的。
若直接拿它生成位流下载，等于把 DDR3 的 CK/CS 等信号打到本板上用途完全不同的管脚
（例如网口 RX_CLK），**有损坏风险且必然跑不通**。
⇒ **已停在这里，没有下载任何 DDR3 位流。**

---

## 1. 已确认的硬件事实（用户答复 + 手册）

| 项 | 值 | 来源 |
|---|---|---|
| 板载 DDR3 颗粒 | **2 颗 `QN3B256M16H-16A::P`（兼容 Micron `MT41K256M16HA-125`）** | 手册 §2.2.3 |
| 单颗容量 / 总容量 | 4 Gbit ×2 = **8 Gbit（1 GB）** | 手册 §2.2.3 |
| **总数据位宽** | **32 bit**（2 颗 x16 并行） | 手册 §2.2.3 + 用户确认 ⇒ 用 **x32** 配置 |
| 最高速率 | DDR3 时钟 ≤ **400 MHz**（数据率 800 Mbps） | 手册 §2.2.3 |
| 连接 Bank | **BANK B3**（DDR-VDDQ = 1.5 V） | 手册 §2.2.3 |
| **系统 50 MHz 时钟** | **P20** | 手册（`FPGA_GCLK_50M P20`）+ 用户确认 |
| 板载其它时钟 | 1 个 125 MHz 有源差分晶振（HSST 参考）+ 1 个单端 50 MHz + 1 个单端 27 MHz | 手册 §2.2.2 |
| `F14` / `Y11` | **不是 50 MHz 时钟源**：F14 = 网口 1 RX_CLK；Y11 = J8 扩展口 | 用户核对手册 |
| DDR3 布局要点 | 单端 50 Ω 走线、DCI 电阻（VRP/VRN）、差分时钟 100 Ω、每颗 ZQ 接 240 Ω 下拉、DDR-VTT 跟随 DDR-VDDQ | 手册 §2.2.3 |

> **P20 是现有工程的 `clk_50m`**（`docs/fpga_platform.md` §3）。DDR3 的 `ref_clk` 若要接 P20，
> 就是与该管脚**共用同一个输入**（PDS 允许一个输入脚驱动多个网络/多个 `create_clock`）。
> 这一点在 S1 里必须实现并实测，见 §4.1。

---

## 2. 本轮已经做出来的东西（可直接复用）

| 产出 | 路径 | 说明 |
|---|---|---|
| 手册管脚表（结构化） | `tmp/ddr3/manual_pins.json` | 从手册表 2-4 抽出的 72 条 `ddr3_* -> 管脚` |
| **按手册重做的管脚映射** | `tmp/ddr3/pinmap_manual.json` | `mem_* -> {pin, standard, vccio, manual_signal}`，**管脚全部来自手册** |
| **可导入的约束片段** | `fpga/ddr3_smoke/constraints/ddr3_pins_from_manual.fdc` | 71 个端口的 `PAP_IO_LOC / VCCIO / STANDARD`；供 IP 的 *Memory Pin Constraint File* 导入 |
| **S1 工程目录** | `fpga/ddr3_smoke/` | 已建好（含 README、约束、配置单、厂商模板对照件）；**与四个既有工程完全隔离** |
| **IP 配置单（96 项）** | `fpga/ddr3_smoke/doc/ip_config_checklist.md` | 72 个 `PAD_*` 管脚已按手册填好（71 个自动填上，`PAD_A15` 说明为"本配置不用"） |
| 生成 + 自检脚本 | `scripts/ddr3_map_manual_pins.py`、`scripts/ddr3_ip_config_checklist.py` | 可重复生成上面各件，带自检 |
| **PDS 校验脚本** | `scripts/run_ddr3_pin_check.ps1` | 把约束丢给 PDS 跑 compile→synthesize→dev_map，**实测 71/71 IO 落地、0 error、0 critical warning** |
| 手册全文（本机副本） | `tmp/ddr3/pangu50kh.pdf` / `.txt` | 官方来源：`https://www.meyesemi.com/upload/202506161424537.pdf` |
| 用户指南全文 | `tmp/hmic_ug.txt` | 由 `UG022003_HMIC_S_IP.pdf` 抽出（54 页） |

### 2.2 约束已经过 PDS 实测（不是只做静态检查）

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\run_ddr3_pin_check.ps1
```

做法：生成一个只声明 71 个 `mem_*` 端口、**含非空逻辑**的桩顶层，交给 PDS 跑
`compile → synthesize → dev_map`，实测：

| 项 | 结果 |
|---|---|
| PDS 退出码 / `E:` 行数 | **0 / 0** |
| "Found N error(s)" | **0 error(s), 0 critical warning(s)** |
| **落地的 IO 管脚数** | **71 / 71** |
| I/O 标准与 VCCIO 冲突 | 无 |

> **踩到的坑（已写进 `fpga/ddr3_smoke/README.md` §3）**：
> 第一版桩顶层是**空模块**，PDS 报 `Create black box for empty module` 并忽略整个顶层，
> 于是 **I/O 约束根本没被检查**，报出来的 "0 error" 是**假通过**。
> 修正后（加三态驱动 + 校验跑到 `dev_map`）才得到上面这份真结果。
> 该脚本**不做布局布线、不出版本**，只操作 `tmp/ddr3/pin_check` 临时工程，不影响任何交付物。

### 2.4 IP 生成**已经全程无 GUI 打通**（2026-09-29）

**结论：不需要点界面。** 一条命令即可产出本板配置的 DDR3 控制器 IP：

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile `
  -ExecutionPolicy Bypass -File scripts\run_ddr3_ip_generate.ps1
```

链路与实测结果：

| 步骤 | 命令 / 脚本 | 实测结果 |
|---|---|---|
| 创建 IP 实例 | `ip_compiler.exe -c -n <名> -i <实例>.ipc -m <IP模型目录> -family Logos -device PGL50H -pack FBG484 -speed -6` | 产出 `.ipc`（XML，**264 个参数**，约 58 KB）|
| 改成本板参数 | `scripts/ddr3_ipc_patch.py` | 改 `<value>`，**并校验新值在该参数的合法列表里**（写错即报错）|
| 生成 IP RTL | `ip_generate.exe -i <实例>.ipc -family … -device …` | `rtl/` 64 文件 + `example_design/` + `pnr/`，`Done: 0 error(s)` |

**生成结果验证**（`fpga/ddr3_smoke/ip/ddr3_mes50hp/ddr3_mes50hp.v`）：

```text
MEM_DQ_WIDTH    = 32      MEM_ROW_WIDTH    = 15
MEM_DQS_WIDTH   =  4      MEM_COLUMN_WIDTH = 10
MEM_DM_WIDTH    =  4      MEM_BANK_WIDTH   =  3
```

产出共 **192 个文件**；`run_ddr3_ip_generate.ps1` **自带位宽校验**，不对就报错退出。

> **最容易踩的坑（实测教训，已写进脚本）**：位宽类参数**必须成组改**。
> 只把 `MEM_DQ_WIDTH` 从 16 改成 32、却留着 `MEM_DQS_WIDTH=2`，生成出的顶层
> **仍然是 16 位** —— 工具发现这组值自相矛盾后**静默回退，且不报错**。
> 必须同时给 `MEM_DQS_WIDTH=4` 与 `MEM_DM_WIDTH=4`（都等于 DQ 位宽 ÷ 8）。
>
> 排查过程中的一个插曲：早先一次测试里 `.ipc` 明明写着 32、`-pre` 脚本用
> `ui::getValue` 也读回 32，生成的却是 16——当时误判成"只能在 GUI 里生效"。
> 真正原因是**位宽参数没成组改**。**这一条说明"看起来像工具限制的问题，先怀疑自己的参数自洽性"。**

**顺带核到的好消息**：`.ipc` 里 IP 的默认值与本板在"器件型号/几何/时钟/分组归属"上**正好一致**
（`DDR_MEM_PART=MT41K256M16xx-15E`、行/列/Bank=15/10/3、`CLKIN_FREQ=50`、
`BANK_CA=B3`、`MEM_TYPE=DDR3`、`OPERATING_MODE=Controller + PHY`）。
但**默认值里的"分组"参数自相矛盾**，必须修正，见 2.4.1——这是布局阶段 `Place-0054` 的真正根因。

### 2.4.1 布局报 `Place-0054` 的根因：`.ipc` 里 15 个分组参数自相矛盾（2026-09-29 定位并修正）

**现象**：`compile` 0 错误、`synthesize` 0 错误（8871 LUT = 20.73%），到 `place` 失败：

```text
Place-0054: IO instance u_dut/I_ddr3_.../i_ca_group[0].u_ddc_ca/opit_0
             must be constrained in same DQS group
```

**先排除的假因**：一度怀疑是 `.fdc` 管脚约束写错。核对后**不是**：
用 `ui::getPkgPinGroup` 问出包内物理 Group 后，四条 byte lane 的
DQ[7:0]/DQS/DQS_n/DM **各自都落在同一个物理 Group 里**，与本板手册完全自洽：

| lane | 管脚所在物理 Group | 与 `.ipc` 的 `GROUP_DQG_*` 是否一致 |
|---|---|---|
| lane0（`mem_dq[7:0]`） | **G5** | 一致（修正后） |
| lane1（`mem_dq[15:8]`） | **G4** | 一致（修正后） |
| lane2（`mem_dq[23:16]`） | **G3** | 一致 |
| lane3（`mem_dq[31:24]`） | **G2** | 一致 |

**真正的根因**：`.ipc` 里每个 CA 信号有**两个**分组参数，出厂默认值里这两处**互相打架**：

```text
GROUP_A1     = G6      # 这根线接在哪个物理 Group（布局据此放 IO）
A1_GROUP_NUM = 2       # 它属于第几个 CA 组槽
CA_GROUP2    = G8      # 第 2 个槽是哪个物理 Group
```

⇒ 同一根线，一处说 G6、一处说 G8。**26 个参与核对的 CA 参数里有 15 个是这种矛盾**，
而且错得有规律：默认的 `CA_GROUP2=G8 / CA_GROUP3=G6` 把 G6、G8 两组**对调**了，
于是物理上在 G6 的 `A1 A2 A6 A8 A9 A14 CAS RAS` 全被标成"槽 2 → G8"。
布局工具于是被要求"把一个 DDC 组里的 IO 摆进同一个 Group"，
可它的**参数自己就说这些 IO 不在同一个 Group**——怎么摆都违反，只能报 `Place-0054`。
**只要不改这组参数，光调 `.fdc` 永远修不好。**

**修正办法**（`scripts/ddr3_ipc_fix_groups.py`，已接入生成流程）：
不猜参数语义，改为"**信号管脚真实所在的物理 Group 是唯一真值**"反推：
`GROUP_<X>` = 该管脚所在物理 Group；`CA_GROUP<n>` = 该槽承载的物理 Group；
`<X>_GROUP_NUM` = 承载它的槽号。修正后的分组（每组就是一个真实物理 Group）：

| CA 组槽 | 物理 Group | 承载信号 | 根数 |
|---|---|---|---|
| 0 | **G0** | BA0 CAS RAS WE ODT CS | 6 |
| 1 | **G1** | A3 A5 A7 | 3 |
| 2 | **G6** | A0 A1 A2 A8 A11 A12 A14 BA2 | 8 |
| 3 | **G8** | A4 A6 A9 A10 A13 BA1 CK CK_n CKE | 9 |

脚本自带两条**断言**，任何一条不成立就报错退出、拒绝产出矛盾配置：
① 每个 CA 信号的"组名 == `CA_GROUP<它的槽号>`"逐条成立；
② 每条 lane 的 `GROUP_DQG_*` 等于该 lane 管脚的真实物理 Group。

> **A15 的说明**：手册有 `ddr3_addr[15] = R7`（物理在 G8），但本 IP 顶层是
> `mem_a[14:0]`（15 位行地址），**没有 `mem_a[15]` 端口**，该信号在本设计里不引出，
> 因此 `A15_GROUP_NUM`/`GROUP_A15` 不影响网表（它们仍留着出厂残留值，脚本显式跳过并打印）。

> **"重新生成 IP 会冲掉手工改动"的坑**：`ip_generate.exe` 会**整体重写** `example_design/`。
> 已知必须重打的厂商文件补丁只有一处——`test_ddr.v` 里的 UART 分频
> `CLK_DIV_P 16'd72 → 16'd434`（原注释写 115200bps，但 50e6/72 ≈ 694k 自相矛盾；
> 且 `test_ddr` 端口表里**没有** `CLK_DIV_P`，无法从例化处覆盖，只能改厂商文件）。
> 已改为 `scripts/ddr3_reapply_vendor_patches.py`（幂等）并在生成脚本第 5 步自动重打。
> 同理，`ip_compiler -c` 会用出厂默认值覆盖 `.ipc`，所以生成脚本**检测到 `.ipc` 已存在就跳过创建**。

### 2.4.2 S1 实测结果（2026-09-29）：**板上通过** `S1 DDR3 SMOKE BOARD PASS`

> ⚠️ 本节曾写"卡在最后 1 根网、判定为硬核拓扑不可满足"。**那个结论是错的**，已被后续实测推翻。
> 错误是如何形成的、又是怎么被纠正的，完整保留在 2.4.3，供后续避免重犯。

**最终状态**：`fpga/ddr3_smoke` 完整跑通
`compile → synthesize → dev_map → place → route → route_optimize → report_timing → gen_bit_stream`，
**0 error**，且**时序全部满足**：

| 指标（Slow 角） | 修好之前 | 最终 |
|---|---|---|
| Setup 最小 WNS | **-0.068 ns**（1 个失败端点） | **+0.367 ns**，失败端点 **0** |
| Hold 最小 WHS | **-0.115 ns**（1 个失败端点） | **+0.044 ns**，失败端点 **0** |
| 另一处 232 个端点的 hold 违例 | WHS -4.411 ns | 消失 |

位流：`fpga/ddr3_smoke/generate_bitstream/mes50hp_ddr3_smoke_top.sbit`
（2101696 bytes，SHA-256 `FAEDF47618647C36FACBFF6DF0E5DE623F20ECD461FFA6997D724ABE93561B76`）。

**板级验收**（`python python\ddr3_smoke_board.py --port COM11 --seconds 8`）：

```text
S1 DDR3 冒烟板级验收: COM11 @ 115200 8N1
  0x80 = 0x00001110  pll_lock=0 dll_lock=1 ddr_init_done=1 err_flag=0
  心跳采样 155 次，翻转 16 次（窗口 8 s）
  0x8B = err_cnt=0 main_state=4 wr_state=0 rd_state=2（15 次采样）
  [PASS] DLL 锁定
  [PASS] DDR3 初始化完成
  [PASS] 心跳在翻转（设计在运行）
  [PASS] 无校验错误标志 err_flag_led
  [PASS] BIST 错误计数全程为 0
  [PASS] BIST 状态机在推进
  [NOTE] pll_lock 状态位恒为 0（已知偏差，见下）
S1 DDR3 SMOKE BOARD PASS
```

**板上 LED 人工判据（用户实测）**：LED1(`B2`) 常亮、LED2(`A2`) 常亮、LED3(`B3`) 闪烁、
LED4(`A3`) 不亮 —— 即 `pll_lock`/`ddr_init_done` 均有效、心跳在跑、无校验错误。

**已知偏差（如实记录，未消除）**：`0x80` 的 bit0（`pll_lock` 状态位）在 31 次连续采样中
**恒为 0**。但它与同寄存器的 `dll_lock`=1、`ddr_init_done`=1、BIST 正常循环、`err_cnt`=0
**不可能同时成立**（这些都要求时钟稳定、PLL 已工作），且板上 LED1 实测常亮，
因此判定**该状态位本身不可信**（极性/连线问题），而不是"PLL 没锁"。
本项不计入通过判据，但必须写进材料，不能含糊过去。

**过程修复清单**（每一步都有独立证据）：

| # | 错误现象 | 根因 | 修法 |
|---|---|---|---|
| 1 | `Place-0054` CA 组 | `.ipc` 里 `GROUP_X` 与 `CA_GROUP_X` 两族参数自相矛盾（15/26 条）；生成器真正读的是 `CA_GROUP_X` 那族 | `scripts/ddr3_ipc_fix_groups.py` |
| 2 | `Place-0084` 专用时钟不可达 | 缺厂商 PHY `PAP_LOC` 约束；路径分隔符是点号、路径里的 `PLL` 是 **generate 块名**必须原样写 | `scripts/ddr3_gen_smoke_fdc.py` |
| 3 | `Place-0242` / `Route-2014` DQ 时钟区 | **`DQ2_EN`/`DQ3_EN` 为 false** —— `ui.tcl` 的 `get_dq_group_number` 只在使能时才给 `GROUP_DQG_*_NUM` 赋值，否则留下越界占位值 **9** | `scripts/ddr3_ipc_patch.py` 置 true |
| 4 | 串口五种波特率全无回应 | **波特率公式算错**：实际是 `clk/(clk_div×6)`（TX 里还有一级 6 分频），我按 `clk/clk_div` 把 72 改成 434，产生 6 倍偏差 | 恢复厂商原值 `16'd72` |
| 5 | 232 端点 hold 违例 + 2 处小违例 | 少一轮 `place/route/route_optimize` 时序优化迭代 | 配方里补一轮 |

**官方例程带来的两条关键校正**（`07_ddr3_test`，本板已跑通的官方工程）：

- **71 个 DDR3 管脚与我们从手册抽取的逐脚完全一致（0 处差异）** → 证明手册解读正确，
  之前"厂商模板与本板不符"的警惕是对的（那份模板确实是另一块板的），但手册本身没错；
- 电平标准应为 **`HSTL15_I`(61 个) / `HSTL15D_I`(10 个：CK 与 4 对 DQS)**，
  不是我们原先按"DDR3 常用"写的 `SSTL15_I`/`SSTL15D_I` —— 接收门限不同，必须改。

**仍未做的事**：`test_ddr` 例程只做 BIST 与状态寄存器，**没有吞吐量/延迟测量**，
所以本次拿到的是"**DDR3 控制器在本板真正工作**"的证据，**不是**"DDR3 性能数字"。
若后续要把 DDR3 作为"真实后端"报数，需要在 Core 外再加一层带计数器的访问器。

### 2.4.3 复盘：那条"硬核拓扑不可满足"的错误结论是怎么来的

**保留这一节的目的**：这条结论当时看起来"证据充分"，还写进了进度文档，事后被证明是错的。
它的错误模式值得记住——**在缺少权威参照时，把"我的推导"当成了"器件的事实"**。

当时的推导链是这样的：

1. 从 IP 前端 `ui.tcl` 读到三张真实的映射表（这三张表本身没错，现在仍在用）：

   | 出处 | 内容 |
   |---|---|
   | `get_dq_group_number` (L3235–3249) | `GROUP_DQG_<k>_NUM` = 物理组名的数字后缀 |
   | `get_region_number` (L3307–3318) | 索引 0/1/2→时钟区0、3/4/5→区1、6/7/8→区2 |
   | `check_region_used` (L3694–3712) | 物理组 G0/G1/G2→区0、**G3/G4/G5→区1**、G6/G7/G8→区2 |

2. 又读到 `I_GTP_DLL` 固定吃 `ddrphy_ioclk[4]`（属区 1），以及 PDS 报
   `IOCKGATE ... max load count is:3`。

3. 于是推出"区 1 最多容纳 2 条 lane"，而本板四条 lane 落在 G5/G4/G3/G2
   ⇒ 区号 1/1/1/0 ⇒ **三条挤在区 1** ⇒ 无解。

**错在哪**：第 3 步把 `GROUP_DQG_<k>_NUM` 的取值当成了"我们可以自由选择的设计变量"，
于是花了好几轮去试不同索引组合（`0,1,3,4` / `5,4,3,2` / `5,4,6,2` / 出厂 `4,5,9,9`），
每组都失败，就顺势得出"无解"。

**真正的答案是第 4 个错误现象**（当时被前三个遮住了）：
**`DQ2_EN`/`DQ3_EN` 本身就是 false**。这两个使能位为 false 时，
`get_dq_group_number` 的 `if` 分支根本不进，`GROUP_DQG_2_NUM`/`GROUP_DQG_3_NUM`
就一直是 proc 开头写下的占位值 **9**（对 9 位 `ddrphy_ioclk` 越界）。
也就是说 lane2/lane3 的时钟索引**从来没有被正确设置过**，
我却拿这个"从未被正确设置的状态"当成约束去推导可行性。
把两个使能位置 true 之后，索引自然变成 3 和 2，**一次构建就通过了**。

**教训**：
- 参数"看起来是默认值"时，要先确认它**是否被真正赋值**（本案例的默认值 9 与"未赋值"是同一回事，
  而正常值只在使能时才会写入）；
- 在宣布"器件约束无解"之前，必须先有一个**该器件上确实能工作的参照**——
  官方例程 `07_ddr3_test` 就是那个参照，它在同一个 IP、同器件、同封装、同管脚表下能跑通，
  这本身就证明"无解"不成立；
- 三次以上"换一组参数再试"都失败时，应当停下来怀疑**前提**，而不是继续穷举。

#### （已作废）旧分析：DQ lane 与时钟区的"约束冲突"

> 本段原判定"硬核时钟拓扑与板级管脚分布不匹配、四方约束联立无解"，**该结论已被推翻**，
> 真正原因是 DQ2_EN/DQ3_EN 为 false 导致 lane2/lane3 的时钟索引从未被赋值（见 2.4.3）。
> 这里只保留当时引用过的三张映射表，因为它们**本身是正确的**、现在仍在用：

| 出处 | 内容 |
|---|---|
| ui.tcl get_dq_group_number (L3235–3249) | GROUP_DQG_<k>_NUM = 物理组名的数字后缀（G5→5、G4→4、G3→3、G2→2） |
| ui.tcl get_region_number (L3307–3318) | 索引 0/1/2→时钟区 0、3/4/5→区 1、6/7/8→区 2 |
| ui.tcl check_region_used (L3694–3712) | 物理组 G0/G1/G2→区 0、G3/G4/G5→区 1、G6/G7/G8→区 2 |
| ddr3_mes50hp_ddrphy_top.v L253 | I_GTP_DLL 固定吃 ddrphy_ioclk[4]（属区 1） |
| ddr3_mes50hp.v L360 | ddrphy_ioclk = {ioclk[2]×3, ioclk[1]×3, ioclk[0]×3} |

> 另外记一个**真实存在但已被绕过**的现象：PDS 报过
> Place-0242: IOCKGATE ... has 4 loads (DQSL: CLK_IO), max load count is:3
> —— 一个 IOCKGATE 确实最多带 3 个 DQSL 负载。把四个 lane 的索引设成同一个值时就会撞上它。
> 最终配置（5/4/3/2）四个索引互不相同，因此不再触发。

### 2.5 仿真可行性：**已确认不可行（如实记录）**

`ipsxb_hmic_s` 的 IP 本体（`rtl/ddrphy/*.vp`、`rtl/mcdq_ctrl/*.vp`）是
**IEEE-1735 加密源码**：文件头是 `` `pragma protect begin_protected ``。
实测 `iverilog` 读 `.vp` 直接报

```text
ipsxb_ddrphy_info_v1_0.vp:1: syntax error
I give up.
```

⇒ **本机无法用 iverilog 仿真 DDR3 控制器**，与 `handoff_next.md` 的预判一致。
按该项目规则：**只做板上验证并如实记录，不得伪造成"仿真通过"**。
（厂商包里另有 `sim_lib/`，但同样是 `.vp`，需要 PDS 自带的仿真流程才能用。）

### 2.6 生成脚本的静态自检结果（全部通过）

```text
映射成功 71 个 DDR3 端口，未匹配 0 个
电平分布: {'SSTL15_I': 61, 'SSTL15D_I': 10}
差分对标准一致（mem_ck/mem_ck_n 与 mem_dqs[i]/mem_dqs_n[i] 均为 SSTL15D_I）
正向核对（生成值 == 手册值）: 71/71 通过
管脚唯一性: 通过（71 个管脚无重复）
与 3.3V 外设管脚冲突: 无
四个 byte lane 的 DQ 分组与手册一致: 是
```

按 byte lane 的最终结果（管脚号即手册值）：

| lane | DQ[7:0] | DQS p / n | DM |
|---|---|---|---|
| 0 | `U1 U3 T2 Y2 T1 Y1 M7 W1` | `V2` / `V1` | `W3` |
| 1 | `P1 M2 R1 M1 P2 L3 P3 N4` | `N3` / `N1` | `L1` |
| 2 | `K4 K1 J3 L4 K3 M3 J1 M4` | `M6` / `L6` | `K2` |
| 3 | `J6 F1 K7 F2 H5 H3 J4 G3` | `E3` / `E1` | `G1` |

其余：`mem_a[0..15] = N6 R4 P6 F3 V5 E4 V3 D2 U4 P5 P8 T4 P7 P4 T3 R7`、
`mem_ba[0..2] = F5 W4 N7`、`mem_ck/ck_n = T6/T5`、`mem_cke = Y3`、`mem_cs_n = G6`、
`mem_ras_n = J7`、`mem_cas_n = H8`、`mem_we_n = H6`、`mem_odt = G7`、`mem_reset_n = C1`。

> 生成脚本已自动核对过"与 `docs/fpga_platform.md` 里 3.3 V 外设（P20/R8/R9/LED/J8/PMOD）
> 无管脚冲突"。后续若改动 `docs/fpga_platform.md` 的固定映射，要重跑一次这个自检。

---

## 3. IP 侧的关键事实（`UG022003_HMIC_S_IP.pdf` V1.7）

配置界面 4 页：Step1 Basic Options → Step2 Memory Options → Step3 Pin/Bank Options → Step4 Summary。

| 页 | 参数 | 厂商默认值 | 本板应填 |
|---|---|---|---|
| Step1 | Memory Type | DDR3 | DDR3 |
| Step1 | Operating Mode | Controller + PHY | 同 |
| Step1 | **Total Data Width** | 16 | **32**（2 颗 x16 并行） |
| Step1 | **Input Clock Frequency** | 50 MHz | 50 MHz（P20） |
| Step1 | Desired Data Rate | 800 Mbps | 800（手册允许到 800 Mbps） |
| Step1 | CWL / CL / AL | 5 / 6 / CL−2 | 同（或按实际颗粒时序） |
| Step2 | SDRAM Device Model | 列表 | **`MT41K256M16xx-15E`**（与 `QN3B256M16H-16A::P` 兼容的型号） |
| Step2 | Row / Column / Bank | 15 / 10 / 3 | 同（4 Gb DDR3） |
| Step3 | **Control/Address Bank** | B3 | **B3**（与手册一致） |
| Step3 | **Data Bank / Group** | B3 / G4 | 需按手册分组核对 |
| Step3 | Memory Pin Constraint File | 可导入 `.fdc` | **导入 `tmp/ddr3/ddr3_pins_from_manual.fdc`**（不能让 IP 用错模板） |

### 3.1 时钟结构（决定 `ref_clk` / `free_clk` 怎么接）

用户指南 §2.8.2 给出内部时钟结构：

```text
ref_clk(50M) --> PLL(倍频) --> GTP_IOCLKBUF --> ioclk[0..2]   （快速 I/O 时钟）
ref_clk(50M) --> PLL(倍频) --> GTP_IOCLKDIV --> ddrphy_clkin  （IP 软逻辑系统时钟）
```

**IP 本身只有 `ref_clk` 一个输入时钟**（另有 `ddr_rstn`、输出 `pll_lock`；见 §2.5.3.1 表 2-16）。
⇒ **`free_clk` 不是 IP 端口，是厂商 Example Design 里给板上其它逻辑（UART/控制）用的时钟。**
因此：

- `ref_clk` **改接 P20**（板上唯一确认的 50 MHz）；
- `free_clk` 也接 P20（或例程实际用途的时钟），**但必须同步处理例程 UART 的分频**：
  例程原本的板载时钟频率与 50 MHz 不同，改成 50 MHz 后 UART 波特率会错，
  直接读 BIST 结果会是乱码。**这是跑 S1 时必须先改掉的一处。**

### 3.2 IO 约束要求（用户指南 §2.8.3，逐条）

- `VCCIO` 必须 **1.5 V**（DDR3 用 1.5 V）；
- `mem_ck` 是差分输出 ⇒ **`SSTL15D_I`**；
- `mem_dqs` 是双向差分 ⇒ **`SSTL15D_I`**；
- 其余信号单端 ⇒ **`SSTL15_I`**；
- `mem_dqs` / `mem_dq` 在 FPGA 端需要端接匹配，**建议用内部端接：`DDR_TERM_MODE = ON`**；
- 其它参数用默认值；
- §2.8.3 还明确：**内部模块（PLL 等）的位置约束来自 `.fdc`，不可改**；
  引脚位置与电平在 UCE 里配置。

> 本轮生成的 `ddr3_pins_from_manual.fdc` 已按上面 4 条电平要求填好
> （61 个 `SSTL15_I` + 10 个 `SSTL15D_I`），与厂商模板的电平写法完全一致。

---

## 4. S1 的修订执行步骤（IP 已生成，接下来是接线与上板）

1. 复制 `ipsxb_hmic_s` 的 Example Design 到**新目录** `fpga/ddr3_smoke/`
   （**不得改动任何交付工程**）；
2. 按 `pnr/prj_filelist.f` 加入源文件，用 `tmp/ddr3/ddr3_pins_from_manual.fdc`
   **替换**厂商那份管脚表（管脚必须来自手册）；
3. **改时钟**：`ref_clk` → `P20`、`free_clk` → `P20`；同步改 `create_clock` 的
   `get_ports` 与管脚约束；
4. **改例程 UART 分频**（否则读不到 BIST 结果），并把 UART 改到板载 CP2102 的 `R9/R8`，
   以便直接用现有上位机脚本读结果；
5. `pds_shell` 综合 → 布局布线 → 时序 → 位流；
6. 下载（`cdt_cfg`；DDR 工程占 Bank 3 的 1.5 V，**不与现有 3.3 V 约束混用**）；
7. 读串口 BIST 结果 → 记录**随机/连续访问延迟与吞吐**（这是"真实后端"的第一组数字）；
8. 仿真：例程自带 `ddr3.v`；本机只有 iverilog，PHY 可能是加密黑盒，
   **跑不动就只做板上验证并如实记录**，不得伪造成"仿真通过"。

**闸门（硬性，照 `handoff_next.md`）**：时间盒 **2 个轮次**；例程在本板上跑不通 →
**停 S2～S4**，把时间转到材料收口（§3.4）与 Fmax（§3.5）。

### 4.1 时钟方案已定：`ref_clk` 与系统时钟共用 **P20**

用户核对手册的结果：**F14 不是板上的固定 50 MHz 时钟**（手册标为网口 1 的 RX_CLK），
**Y11 是 J8 扩展口引脚**；板载 50 MHz 晶振接 **P20**。
⇒ 厂商例程的 `ref_clk=F14` / `free_clk=Y11` 在本板都不可用。

**决定（2026-09-29，用户已授权 Agent 自行判断）**：

- `ref_clk`（IP 的参考时钟）→ **P20**；
- `free_clk`（**不是 IP 端口**，是例程给板级逻辑用的时钟）→ **P20**；
- 一个输入脚共用给多个网络、多个 `create_clock` 在 PDS 里是允许的，
  但 DDR 工程与现有工程时钟树不同，**必须单独建工程、单独验证**；
- 将来若改用板载 27 MHz 单端晶振，只需改这一处（需先补它的管脚号与电平，
  本轮从手册文本里没抽到）。

---

## 5. 与范围纪律的关系（**已由用户批准改写**）

原状：`AGENTS.md` §1.14 写着"本届仍明确不实现 I-Cache、D-Cache、burst…"，
而 S2～S4 要做行式突发与 2 路 I/D Cache，因此进入 S2 之前必须由用户决定并改写 §1.14。

**进展（2026-09-29）**：

- 用户当时的答复是"暂不改，等 S1 真跑通再决定" ⇒ 本轮与 S1 都没动范围纪律；
- **S1 已于同日板上通过**（`S1 DDR3 SMOKE BOARD PASS`，见 §2.4.2），闸门条件满足；
- 随后用户**批准改写**：I-Cache / D-Cache / burst / 外部 DDR3 由"本届不做"改为"本届要做"；
  `AGENTS.md` §1.14 正文与 §4/§8/§9 三处引用已同步，其余 7 个文档 9 处旧表述由
  `scripts/apply_scope_change.py` 精确落地（可 `--check` 复检）。

**改写时写死的边界（不得放宽）**：I-Cache 只能在取指端口与下级存储之间，
D-Cache 只能在数据端口与 SoC 互连之间，**`rtl/pipeline_cpu.v` 端口与事务语义不变**，
MMIO 恒为 uncacheable，Cache/突发全部位于 Core 外部；
每完成一步必须重跑 Trap 契约全部断言 + 最终回归 + CoreMark，任何退化即回退。
