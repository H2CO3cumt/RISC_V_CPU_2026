# HMIC_S IP 界面操作手卡（照着点就行）

> 目标：生成一份**适配本板 MES50HP** 的 DDR3 控制器 IP。
> 全程只需要在 PDS 的 IP Compiler 界面上点 **3 处**，其余照抄本文。
> 参数与管脚的来源：MES50HP 官方硬件手册表 2-4 + IP 用户指南 `UG022003_HMIC_S_IP.pdf`。
> 完整背景见 `docs/ddr3_s1_survey.md`；本文件只讲"手怎么动"。

---

## 0. 打开界面

双击运行：

```text
D:\Pango\PDS_2024.2-SP2\bin\ip_compiler.exe
```

（这是"IP 编译器"独立程序，不用先开 PDS；左栏能看到 IP 列表。）

---

## 1. 新建实例

1. 左栏 IP 列表里找到 **`DDR3 Interface`**（版本 **1.7**，厂商 Pango）。
   —— 这就是 `ipsxb_hmic_s`，是**唯一**支持 PGL50H 的那份；别选到 `DDR3 Interface (2L)` 之类的。
2. 选中它 → 点 **`[Customize]`**（或直接双击）。
3. 弹窗问器件信息，填：
   - Family = **Logos**
   - Device = **PGL50H**
   - Package = **FBG484**
   - Speed Grade = **-6**
4. 实例名（Instance Name）随便取，例如 **`ddr3_mes50hp`**。
   输出目录建议放到 **`D:\RISC_V_CPU_2026\fpga\ddr3_smoke\ip\`**（本工程目录，与交付工程隔离）。

---

## 2. **要点的第 1 处：Step 1 Basic Options**

界面左上角有 4 个步骤页：`Step1 Basic Options` → `Step2 Memory Options` →
`Step3 Pin/Bank Options` → `Step4 Summary`。按顺序填。

在 **Step 1** 里改这几项（其余保持默认）：

| 界面上的字段 | 填什么 | 说明 |
|---|---|---|
| `Memory Type:` | `DDR3` | 默认就是，不用改 |
| `Operating Mode:` | `Controller + PHY` | 默认就是，不用改 |
| **`Total Data Width:`** | **`32`** | ⚠️ **默认是 16，必须改成 32**（板上 2 颗 x16 颗粒并行） |
| `Input Clock Frequency:` | `50` MHz | 默认就是 50，确认一下 |
| `Desired Data Rate:` | `800` Mbps | 默认就是，不用改 |
| `CAS Write Latency(CWL)` / `CAS Latency(CL)` / `Additive Latency(AL)` | 5 / 6 / 0 | 默认就是，不用改 |

> **就改一项：`Total Data Width` 16 → 32。**

## 3. **要点的第 2 处：Step 2 Memory Options → 选器件型号**

在 **`SDRAM Device Model`** 下拉框里选：

```text
MT41K256M16xx-15E
```

**为什么是它**：板上是 2 颗 `QN3B256M16H-16A::P`，官方手册写明它**兼容 Micron
`MT41K256M16HA-125`**，而这个 IP 支持的型号列表里最接近的就是 `MT41K256M16xx-15E`。
（`xx` 是速度/温度后缀，功能一致。）

> 下拉框里**不要**选 `Create Custom Part`（那要自己填一堆时序参数，没必要）。
> Row / Column / Bank Address 会跟着型号自动变成 **15 / 10 / 3**，正好对。

## 4. **要点的第 3 处：Step 3 Pin/Bank Options → 指定管脚文件**

这一步**最要紧**，做错了会打到网口管脚上去。

### 4.1 勾选"用自定义 FDC 文件"

- 找到复选框 **`Enable fdc file select`**（旁边文字：
  "Please select a fdc file which contains default memory pins constraint."）→ **勾上**
- 旁边的文本框 / **`Browse...`** 按钮 → 选这个文件：

```text
D:\RISC_V_CPU_2026\fpga\ddr3_smoke\constraints\ddr3_pins_from_manual.fdc
```

> ⚠️ **绝对不要**选 PDS 自带的那份 `50h_ddr3_fbg484_b3_x32.fdc`：
> 它名字看着最像，但实测 **69 个管脚里 65 个与本板不符**
> （比如它写 `mem_ck=F3`，而本板 `F3` 其实是 `ddr3_addr[3]`）。
> 选错了等于把 DDR3 的时钟信号接到网口上，**有损坏风险**。
> 本工程 `constraints\` 下那份是我们按手册重新生成的，已通过 PDS 校验（71/71 管脚落地、0 错误）。

### 4.2 勾上 `Enable CS_n`

界面里有一项：

```text
Enable CS_n(if cs_n is disabled,it should be considered NF maintained LOW through an external resister to GND)
```

→ **勾上**（本板的 `mem_cs_n` 是接了的，管脚 `G6`）。

### 4.3 `Control/Address Bank` 选 `B3`

下拉框 `Control/Address Bank:` → 选 **`B3`**（DDR3 接在 Bank 3）。

### 4.4 核对管脚表（关键防错步骤）

导入 FDC 之后，界面下半部会列出 **Signal Name / Group Number / Pin Number** 三列。
**请逐行核对**，必须是下面这些值：

| 信号 | 管脚 | | 信号 | 管脚 |
|---|---|---|---|---|
| `RESET` | **C1** | | `BA0` | **F5** |
| `CKE` | **Y3** | | `BA1` | **W4** |
| `CK` | **T6** | | `BA2` | **N7** |
| `CK_N` | **T5** | | `A0` | **N6** |
| `CS` | **G6** | | `A1` | **R4** |
| `RAS` | **J7** | | `A2` | **P6** |
| `CAS` | **H8** | | `A3` | **F3** |
| `WE` | **H6** | | `A4` | **V5** |
| `ODT` | **G7** | | `A5` | **E4** |
| `A6` | **V3** | | `A11` | **T4** |
| `A7` | **D2** | | `A12` | **P7** |
| `A8` | **U4** | | `A13` | **P4** |
| `A9` | **P5** | | `A14` | **T3** |
| `A10` | **P8** | | `A15` | **不用填**（见下） |

**数据脚（DQ/DQS/DM）按 byte lane 分组**，也必须对：

| lane | DQ[7:0] | DQS p / n | DM |
|---|---|---|---|
| 0 | `U1 U3 T2 Y2 T1 Y1 M7 W1` | `V2` / `V1` | `W3` |
| 1 | `P1 M2 R1 M1 P2 L3 P3 N4` | `N3` / `N1` | `L1` |
| 2 | `K4 K1 J3 L4 K3 M3 J1 M4` | `M6` / `L6` | `K2` |
| 3 | `J6 F1 K7 F2 H5 H3 J4 G3` | `E3` / `E1` | `G1` |

> **`A15` 留空是正常的**：IP 的行地址宽度是 15（`mem_a[14:0]`）。
> 板子手册里 `ddr3_addr[15]=R7` 属于"板上确实有线、但这个配置用不到"，
> **接上去反而与 IP 端口宽度不符**。看到它空着不用管。

**如果某几个管脚自动填得跟上面不一样**：勾上界面里的
**`Custom Control/Address Group`**，然后照上表手工把 `Pin Number` 改过来
（IP 用户指南也建议这种"自定义分组"方式，因为 PCB 走线各不相同）。

---

## 5. **点 Generate**

核对完点 **`[Generate]`**（工具栏上的生成按钮，或菜单 `Project → Generate`）。

- 会弹出问是否同时综合 → 选**是**（也可以先不综合，后面用脚本做）。
- 生成过程会切到 `Log` 页打印信息。

**成功的标志**：Log 页最后出现 `Done: 0 error(s)`，并且实例目录里出现
`rtl\`（约 64 个文件）、`example_design\`、`pnr\` 这些文件夹。

---

## 6. 生成完之后

把**实例目录的完整路径**告诉 Agent（例如
`D:\RISC_V_CPU_2026\fpga\ddr3_smoke\ip\ddr3_mes50hp`），后面这些 Agent 来做：

1. 改 `ref_clk` / `free_clk` 接 **P20**；
2. 改例程 UART 的分频，并把串口改到板载 `R9`/`R8`；
3. 加入例程源文件、跑 `pds_shell` 综合 → 布局布线 → 位流；
4. 下载读 BIST 结果，记录**随机/连续访问延迟与吞吐**。

> 在此之前**不要**下载任何 DDR3 位流——管脚没核对完就上板是有风险的。

---

## 附：如果卡住了

| 现象 | 怎么办 |
|---|---|
| 找不到 `DDR3 Interface` | 确认选的是 **Pango** 厂商、**1.7** 版本；PGL50H 只在这份里支持 |
| `Total Data Width` 里没有 32 | 说明选错 IP 了（支持列表是 8/16/24/32/40/48/56/64） |
| 器件型号下拉里没有 `MT41K256M16xx-15E` | 截图给 Agent；备选是 `MT41J256M8xx-15E`（x8 颗粒，需确认板子实际接法） |
| 导入 FDC 后管脚与上表不符 | 勾 `Custom Control/Address Group` 手工改，或截图给 Agent |
| 界面里 `B1` 而不是 `B3` | 手动把 `Control/Address Bank` 改成 **B3** |
| 点了 Generate 报错 | 把 `Log` 页内容复制给 Agent |
