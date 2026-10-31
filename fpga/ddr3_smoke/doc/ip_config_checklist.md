# HMIC_S IP 配置单（按 MES50HP 本板填好）

> 由 `scripts/ddr3_ip_config_checklist.py` 从 `createFiles.tcl` 的参数名 + 手册管脚表生成。
> `example_design/rtl/test_ddr.v` 只是 `test_ddr.v.xml` 这个 **IP 配置模板**，
> 可综合源码必须由 PDS 的 IP 生成器按这份参数表生成。

## 1. 固定参数（本板确定值）

| 参数 | 本板取值 | 依据 |
|---|---|---|
| `MEM_TYPE` | **DDR3** | IP 当前只支持 DDR3 |
| `DDR_MEM_PART` | **MT41K256M16xx-15E（与板载 QN3B256M16H-16A::P 兼容）** | 板载 2×QN3B256M16H-16A::P，手册 §2.2.3 |
| `MEM_DQ_WIDTH` | **32** | 2 颗 x16 并行 = 32 bit，手册 §2.2.3 |
| `MEM_DQS_WIDTH` | **4** | 32 bit / 8 = 4 个 byte lane |
| `CLKIN_FREQ` | **50** | 板载 50 MHz 接 P20 |
| `ACTUAL_RATE` | **800** | 手册允许到 800 Mbps |
| `OPERATING_MODE` | **Controller + PHY** | 控制器 + PHY |
| `BANK_CA` | **B3** | DDR3 接 Bank 3，手册 §2.2.3 |
| `MEM_ADDR_WIDTH` | **15** | 4 Gb DDR3 |
| `MEM_BANK_WIDTH` | **3** | 4 Gb DDR3 |
| `MEM_COLUMN_WIDTH` | **10** | 4 Gb DDR3 |

## 2. 非管脚参数（需在 IP 界面逐项确认）

| 参数名 | 建议值 / 说明 |
|---|---|
| `CUSTOMIZE_MEM` | 0（用上面列出的标准器件型号） |
| `CA_GROUP_NUM` | 按手册 byte lane 分组核对（见 §3 的 DQ 分组） |
| `REGION_NUM` | 默认 |
| `DEVICE_100H_50G` | 默认（PGL50H） |
| `GROUP_DQG_0` | 按手册 byte lane 分组核对（见 §3 的 DQ 分组） |
| `GROUP_DQG_1` | 按手册 byte lane 分组核对（见 §3 的 DQ 分组） |
| `GROUP_DQG_2` | 按手册 byte lane 分组核对（见 §3 的 DQ 分组） |
| `GROUP_DQG_3` | 按手册 byte lane 分组核对（见 §3 的 DQ 分组） |
| `STATIC_RATIOF` | 默认（PHY 静态比值，由 IP 按频率算出） |
| `STATIC_RATIOI` | 默认（PHY 静态比值，由 IP 按频率算出） |
| `STATIC_RATIO0` | 默认（PHY 静态比值，由 IP 按频率算出） |
| `USER_PINS_CON_EN` | **1**（Enable：启用手工管脚约束，配合 USER_FDC_PATH 导入下面的 FDC） |
| `USER_FDC_PATH` | **指到 `tmp/ddr3/ddr3_pins_from_manual.fdc`**（用户指南 Step3：勾选后可导入 FDC，自动读入 Control/Address 与 Data 管脚） |
| `CS_n_EN` | **1**（厂商模板约束了 `mem_cs_n`，说明该板按"启用 CS_n"配置；本板同理） |

## 3. PAD_* 管脚参数（共 72 个，管脚已按手册填好）

| 参数名 | 手册管脚 | 参数名 | 手册管脚 |
|---|---|---|---|
| `PAD_RESET` | **C1** | `PAD_DQ8` | **P1** |
| `PAD_CKE` | **Y3** | `PAD_DQ9` | **M2** |
| `PAD_CK` | **T6** | `PAD_DQ10` | **R1** |
| `PAD_CKN` | **T5** | `PAD_DQ11` | **M1** |
| `PAD_CS` | **G6** | `PAD_DQ12` | **P2** |
| `PAD_RAS` | **J7** | `PAD_DQ13` | **L3** |
| `PAD_CAS` | **H8** | `PAD_DQ14` | **P3** |
| `PAD_WE` | **H6** | `PAD_DQ15` | **N4** |
| `PAD_ODT` | **G7** | `PAD_DQ16` | **K4** |
| `PAD_BA0` | **F5** | `PAD_DQ17` | **K1** |
| `PAD_BA1` | **W4** | `PAD_DQ18` | **J3** |
| `PAD_BA2` | **N7** | `PAD_DQ19` | **L4** |
| `PAD_A0` | **N6** | `PAD_DQ20` | **K3** |
| `PAD_A1` | **R4** | `PAD_DQ21` | **M3** |
| `PAD_A2` | **P6** | `PAD_DQ22` | **J1** |
| `PAD_A3` | **F3** | `PAD_DQ23` | **M4** |
| `PAD_A4` | **V5** | `PAD_DQ24` | **J6** |
| `PAD_A5` | **E4** | `PAD_DQ25` | **F1** |
| `PAD_A6` | **V3** | `PAD_DQ26` | **K7** |
| `PAD_A7` | **D2** | `PAD_DQ27` | **F2** |
| `PAD_A8` | **U4** | `PAD_DQ28` | **H5** |
| `PAD_A9` | **P5** | `PAD_DQ29` | **H3** |
| `PAD_A10` | **P8** | `PAD_DQ30` | **J4** |
| `PAD_A11` | **T4** | `PAD_DQ31` | **G3** |
| `PAD_A12` | **P7** | `PAD_DQS0` | **V2** |
| `PAD_A13` | **P4** | `PAD_DQSN0` | **V1** |
| `PAD_A14` | **T3** | `PAD_DQS1` | **N3** |
| `PAD_A15` | **?** | `PAD_DQSN1` | **N1** |
| `PAD_DQ0` | **U1** | `PAD_DQS2` | **M6** |
| `PAD_DQ1` | **U3** | `PAD_DQSN2` | **L6** |
| `PAD_DQ2` | **T2** | `PAD_DQS3` | **E3** |
| `PAD_DQ3` | **Y2** | `PAD_DQSN3` | **E1** |
| `PAD_DQ4` | **T1** | `PAD_DM0` | **W3** |
| `PAD_DQ5` | **Y1** | `PAD_DM1` | **L1** |
| `PAD_DQ6` | **M7** | `PAD_DM2` | **K2** |
| `PAD_DQ7` | **W1** | `PAD_DM3` | **G1** |

## 4. 自检

- PAD_* 参数总数：**72**
- 能从手册表自动填上管脚的：**71**
- 需要人工判断的：**1** → ['PAD_A15']
- 管脚来源：MES50HP 硬件手册表 2-4（**不是**厂商模板，那份模板 65/69 个管脚与本板不符）

## 5. 两处必须知道、否则会"以为漏了管脚"的地方

1. **`PAD_A15` 不用接**。IP 的 `MEM_ROW_ADDR_WIDTH` 默认是 **15**
   （`test_ddr.v.xml` 第 31 行，可选 12/13/14/15），于是端口是 `mem_a[14:0]`；
   厂商模板也只约束到 `mem_a[14]`。
   手册里 `ddr3_addr[15] = R7` 是**板上确有走线但本配置不使用**的管脚 ⇒
   **不要**把它接到 `PAD_A15` 上（接了反而与 IP 的端口宽度不符）。
2. **IP 的复位端口是 `mem_rst_n`**，对应参数 `PAD_RESET`，手册管脚 **C1**
   （手册信号名是 `ddr3_reset_n`）。命名不一致，容易看漏。
