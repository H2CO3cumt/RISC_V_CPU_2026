# CoreMark 跑分复现说明（一页）

> **目的**：拿到本交付包的人，**不依赖任何开发工作区**，就能在这块 MES50HP 上
> 自己下载位流、自己跑出 CoreMark 分数，并自行核对官方 CRC。
>
> 本包内所有文件都是自带的；下面命令里的相对路径都以 **本包根目录**为基准。

---

## 1. 复现结果（应当跑出的数字）

| 项 | 值 |
|---|---|
| 位流 | `bitstream/mes50hp_coremark_85m.sbit` |
| 位流 SHA-256 | `751C692B8780E3F05BD6D86E8E0F8BA34A83AFE899E5DA86FE7474C49CA970E9` |
| CPU 时钟 | **85.000 MHz**（板载 50 MHz 晶振 → 片上 PLL） |
| 迭代次数 | 2500 |
| **CoreMark 分数** | **79.587** |
| **CoreMark/MHz** | **0.936** |
| 总 ticks | 2,670,014,377 |
| 运行时间 | 31.412 s（= ticks ÷ 85 000 000） |
| 官方 CRC 校验 | **PASS**（`Correct operation validated.`） |

> 位流是**跑分专用**配置，与本包的另一颗交付位流
> `bitstream/mes50hp_riscv_logic_analyzer.sbit`（逻辑分析仪应用）**不是同一个文件**。
> 跑 CoreMark 必须用这颗。

> ✅ **本流程已实测验证（2026-09-30）**：把交付 zip 解压到一个**干净目录**，
> 只用包内的位流与包内的 `tools/coremark_serial.py` 走了一遍上面第 3～5 步，
> 实跑得到 `ticks=2670014377`、`Score 79.587`、`CoreMark/MHz 0.936`、四个官方 CRC 全同、
> `flush` 相同 —— 与第 5 节金标准一致（仅 `PERF` 行的窗口敏感计数器不同，原因见第 5 节）。
> 记录见 `release/evidence/delivery_package_reproduction/`。

---

## 2. 需要的器材

- MES50HP 开发板（紫光同创 Logos `PGL50H-6IFBG484`），USB 线接上
- 紫光同创 PDS 2024.2-SP2（用于下载位流；用 PDS Programmer 即可）
- **跑分上位机：不需要额外安装任何东西**——包内 `跑分.cmd` 用 Windows 自带的 PowerShell 与 .NET 串口。
  （想用命令行/Python 的也有：`tools/coremark_serial.py`，需 `pip install pyserial`）
- 串口参数：**115200 8N1**，板上是 CP2102

---

## 3. 步骤一：下载位流

> 包内**同时提供了可选打开的 PDS 工程** `MES50HP_CoreMark_85M.pds`（与逻辑分析仪工程同级同形）。
> 只想下载的话不需要它——下面方法 B 用 PDS Programmer 直接选 `.sbit` 即可；
> 想在 PDS GUI 里看源码/约束/重建，或者习惯"先开工程再下载"，用方法 A。

**方法 A（打开包内跑分工程，再下载）**

1. PDS 2024.2-SP2 → `File` → `Open Project` → 选包根目录的 `MES50HP_CoreMark_85M.pds`
2. 打开后可以看到：Top = `mes50hp_coremark_pll_top`、源文件在 `rtl/`、约束 `constraints/mes50hp_coremark_85m.fdc`
3. 用 PDS 的 **Programmer / 下载** 工具选 `bitstream/mes50hp_coremark_85m.sbit` 下载
   （或直接 `Run` 走一遍 Compile→…→Bitstream，产物落在 `generate_bitstream/`）

**方法 B（只要位流，不需要工程）**

1. 打开 PDS → **Programmer / 下载** 工具
2. 选择器件 `PGL50H-6IFBG484`，链路上应看到一个器件
3. 选择文件 `bitstream/mes50hp_coremark_85m.sbit`
4. 点下载 → 提示 **`The done bit is 1`** 即成功

**方法 C（命令行，仅开发仓库里有这个脚本）**

```powershell
scripts\program_board.ps1 -Config cm85      # 自动下载上面这颗跑分位流
```

> ⚠️ **下载后不要按复位**。这颗位流是 `AUTOSTART=0`：上电后固件在等串口发一个
> 字符 **`R`** 才开始跑。不按复位、直接进下一步即可。

---

## 4. 步骤二：跑分

**方法 A（推荐，零依赖：Windows 自带功能，不需要装 Python）**

**双击包根目录的 `跑分.cmd`**。它会：

1. 自动找到板载 CP2102 串口（也可以右键编辑该 `.cmd` 里的 `-Port COM11` 手动指定）；
2. **每秒发一个字符 `R`** 启动固件（这颗位流是 `AUTOSTART=0`，不发就一直不动）；
3. 收到 `COREMARK_DONE` 结束（正常约 **32 秒**）；
4. 落盘三样东西到 `results\coremark\`：
   - `coremark_uart.log` —— 板子原始串口输出（第一手证据）
   - `coremark_board.json` —— 解析出的 ticks / 分数 / 秒数 / CRC / CPI
   - **`跑分结果.html`** —— 一张自包含结果页，**双击用浏览器打开**就能看分数与逐项金标准核对；
5. 判据与 Python 版完全一致：四个官方 CRC、`Correct operation validated.`、运行时间 ≥10 秒；
   不一致则打印 `COREMARK SCORE FAIL` 并以非零码退出。

**方法 B（装了 Python 也能用同一条路）**

```powershell
py -3 tools\coremark_serial.py COM11 --clock-hz 85000000 --output coremark_run.log --summary coremark_run.json
```

- `--clock-hz 85000000` **必须给**：它把 ticks 换算成秒，并按赛题要求检查"运行时间 ≥10 秒"；
- 两者协议与判据相同（`python/coremark_serial.py` 与 `tools/coremark_score.ps1` 是同一套）。

**方法 C（连 `.cmd` 都不想用）**：任意串口工具打开 115200 8N1，**反复发送字符 `R`**，
把串口输出存下来即可（约 32 秒后出现 `COREMARK_DONE`）；拿到日志后也可以用
`tools\coremark_score.ps1 -FromLog <日志文件>` 离线判读并生成结果页。

> 无论走哪条路：运行约 32 秒，**不要中途拔线**；期间不要用别的程序占用该串口。

---

## 5. 步骤三：核对输出

串口应当出现下面这段（`expected/coremark_expected_output.txt` 是同一份金标准）：

```text
COREMARK_START
2K performance run parameters for coremark.
CoreMark Size    : 666
Total ticks      : 2670014377
Total time (secs): 31
Iterations/Sec   : 80
Iterations       : 2500
Compiler version : GCC 15.2.0
Compiler flags   : -O2 -march=rv32i -mabi=ilp32
Memory location  : STATIC BRAM
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0x5275
Correct operation validated. See README.md for run and reporting rules.
CoreMark score x1000 : 79587
CoreMark/MHz x1000  : 936
PERF cycle=<每次不同> instret=<每次不同> stall=<每次不同> load=<每次不同> branch=<每次不同> taken=<每次不同> flush=098f24f4
COREMARK_DONE
```

### ⚠️ 哪些**必须**一致、哪些**允许**不同

**这条很重要，否则你会误判成"复现失败"：**

| 字段 | 是否必须一致 | 说明 |
|---|---|---|
| `Total ticks` = 2670014377 | ✅ **必须一致** | 计时基准 |
| `CoreMark score x1000` = 79587 | ✅ **必须一致** | 计分依据 |
| `CoreMark/MHz x1000` = 936 | ✅ **必须一致** | 该指标与频率无关 |
| `[0]crclist/crcmatrix/crcstate/crcfinal` | ✅ **必须一致** | EEMBC 官方 CRC，`0xe714 / 0x1fd7 / 0x8e3a / 0x5275` |
| `Correct operation validated.` | ✅ **必须出现** | 官方自校验通过 |
| `Iterations` = 2500、`CoreMark Size` = 666 | ✅ **必须一致** | 运行参数 |
| **`PERF` 行里除 `flush` 之外的计数器** | ❌ **允许不同** | 见下 |
| `flush` = `098f24f4` | （同一批次内稳定） | 两次实跑相同 |

**为什么 `PERF` 行会变**：那是**板级性能计数器**的原始值，它的统计窗口与 CoreMark 的计时窗口
**不完全重合**，窗口边界每次会差几个周期，于是 `cycle`/`instret`/`stall`/`load`/`branch`/`taken`
每次都有约 ±1% 的抖动。
**这不是错误**：`ticks` 与分数**逐位不变**，说明程序执行完全一致，抖动只发生在计数器的取样边界上。

> 因此**不要拿 `PERF` 行的绝对值当合格判据**，也不要据此算 CPI 并写成精确值 ——
> 本设计实测过同一颗位流两次运行 CPI 为 1.494 与 1.508，而 ticks 与分数完全一致。
> **CPI 只能写 ≈1.50。**

### 核对清单（照这个逐条打勾）

1. `Correct operation validated.` 出现 —— 四个官方 CRC 均如上，**EEMBC 自校验通过**；
2. `Total ticks : 2670014377`；
3. `CoreMark score x1000 : 79587` ⇒ 分数 **79.587**；
4. `Iterations : 2500` + 85 MHz ⇒ 31.412 s，**满足赛题"运行时间不低于 10 秒"**；
5. 分数公式（赛题指南原文）：`Score = CoreMark_Iterations / (Total_Time × Frequency)`，
   本配置折算出 **CoreMark/MHz = 0.936**。

---

## 6. 想从源码重建位流（可选）

### 6.1 用包内工程重建（推荐，一条命令）

包根目录的 `MES50HP_CoreMark_85M.pds` 就是这颗跑分位流的工程，配方是 `build_coremark_pds.tcl`：

```powershell
cd <包根目录>
& 'D:\Pango\PDS_2024.2-SP2\bin\pds_shell.exe' -file build_coremark_pds.tcl -project_name coremark_rebuild
```

跑完产物在 `generate_bitstream/mes50hp_coremark_pll_top.sbit`。
（在 PDS GUI 里也可以直接打开工程后点 Run 走同一条流程。）

> 已验证（2026-10-03）：交付包副本上用该配方跑到 `dev_map` 为
> `EXITCODE=0`、24 s、`Found 0 error(s) … out of 45 constraint(s)`，
> 三个存储器镜像 `rtl/coremark_{imem,drom,ram}.mem` 均按 `$readmemh` 正确加载，
> `synthesized` 与 `mapped` 均成功。

### 6.2 从 C 源码重新编译固件

本包按**与开发仓库相同的相对目录结构**存放，因此固件 Makefile 可以原样使用：

```powershell
cd coremark\software\coremark
$env:RISCV_PREFIX = 'riscv-none-elf-'      # 官方指南写 riscv32-unknown-elf-gcc，本项目用 xPack 前缀
make all ITERATIONS=2500 CLOCK_HZ=85000000 AUTOSTART=0 PERF_WINDOW_ALIGN=0
```

产出 `build/coremark_imem.mem` / `build/coremark_dmem.mem`，与包内
`coremark/images/` 下随位流一起提供的镜像应当一致。

**目录说明**

| 目录 | 内容 |
|---|---|
| `MES50HP_CoreMark_85M.pds`（包根） | **跑分位流的 PDS 工程**：Top `mes50hp_coremark_pll_top`，直接打开即可查看/重建/下载 |
| `build_coremark_pds.tcl`（包根） | 跑分工程的命令行重建配方（Compile→…→Bitstream） |
| `rtl/`（包根） | 两个工程**共用**的 CPU/SoC 源码；另有跑分专用 `coremark_program_memory.v`、`mes50hp_coremark_pll_top.v` 与 `coremark_{imem,drom,ram}.mem` 镜像 |
| `constraints/mes50hp_coremark_85m.fdc` | 跑分工程约束（与逻辑分析仪工程的 `.fdc` 并列） |
| `coremark/software/coremark/` | 跑分固件工程（`start.S`、`core_portme.c/h`、`ee_printf.c`、`link.ld`、`Makefile`） |
| `coremark/third_party/coremark/` | **EEMBC 官方 CoreMark v1.0 源码**（`core_*.c`、`coremark.h`、`LICENSE.md`）——未改动 |
| `coremark/images/` | 实际烧进 FPGA 的镜像（`coremark_imem.mem`、`coremark_drom.mem`、`coremark_ram.mem`）与存储器 RTL |
| `coremark/rebuild/` | PDS 重建配方（`pds_recipe.tcl`）、约束（`.fdc`）、顶层与 PLL（`pll_85m.v`） |
| `coremark/expected/` | 金标准串口输出，供逐行比对 |
| `coremark/scripts/` | 编译后 ISA 自检脚本（确认产物是纯 RV32I） |

> 固件源码里带 `PERF_WINDOW_ALIGN` 开关（默认 0），它只影响**性能计数器窗口的对齐方式**，
> **不改变被测量的执行路径**；默认关闭是为了与历史镜像逐字节可比。

---

## 7. 常见坑

| 现象 | 原因 / 处理 |
|---|---|
| 串口一直没输出 | 位流是 `AUTOSTART=0`，**必须发 `R`** 才开跑；用上面的脚本会自动发 |
| 输出乱码 | 波特率不是 115200，或 8N1 设错 |
| 下载后 `done bit` 不是 1 | 器件/链路没选对；换个 USB 口或重开 PDS Programmer |
| 分数不对 | 先确认跑的是 `mes50hp_coremark_85m.sbit`（跑分专用位流），不是逻辑分析仪那颗 |
| 时间算出来是 53 秒 | 那是**按 50 MHz 算的**。本配置是 85 MHz，真实耗时 31.412 s；命令行要带 `--clock-hz 85000000` |

---

## 8. 其它实测频点（不在本包内，仅供对照）

本设计在同一板卡上实测过四个频点，`CoreMark/MHz` 恒为 **0.936**，四点严格成比例：

| 频率 | CoreMark 分数 |
|---|---|
| 50 MHz | 46.816 |
| 80 MHz | 74.905 |
| **85 MHz（本包，交付时钟）** | **79.587** |
| 90 MHz | 84.269 |

按要求只把**与交付时钟一致的 85 MHz** 跑分件放进本包。
90 MHz 是 CPU 的板级上界；完整逻辑分析仪应用在 90 MHz 下 SPI 模式不工作，因此交付取 85 MHz。
