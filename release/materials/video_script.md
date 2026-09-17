# 三分钟演示视频脚本

> 版本：competition final candidate
> 作品：RISC-V多协议逻辑分析仪
> 目标时长：180 秒

## 0 到 18 秒 作品定位

画面：MES50HP 开发板、PDS 工程与作品名称同屏。

旁白：本作品在盘古 50 FPGA 上实现 RV32I 五级流水线处理器，并在处理器外部集成可重构八通道逻辑分析仪。CPU 支持数据前递、Load-Use 暂停和分支冲刷；应用通过统一 MMIO 接口连接，外设变化不修改流水线主体。

## 18 到 48 秒 正确性证据

画面：最终回归摘要、Single Cycle 与 Pipeline trace 首差比较示例、RV32UI 测试结果。

旁白：单周期 CPU 作为参考模型。自动回归覆盖完整 RV32I 定向测试、上游 RV32UI Core 29 项与 Memory 10 项、GCC 程序、随机背压和 Reset。流水线按退休顺序比较 PC、指令、寄存器写回与内存写入，当前所有自动化入口通过。

## 48 到 80 秒 流水线与性能

画面：IF、ID、EX、MEM、WB 数据通路；前递、暂停和冲刷的关键路径；PDS 时序表。

旁白：流水线在 EX 级处理数据相关，在 Load-Use 时插入 Bubble，在 Branch 和 Jump 确认后冲刷错误路径。正式 CoreMark 配置的 PDS 结果为 2438 LUT、1333 FF、33 DRM，50 MHz 约束通过，估算 Fmax 为 68.2594 MHz。RTL 仿真通过官方 CRC，估算 CoreMark 每 MHz 为 0.520000；实体板成绩将在现场脚本运行后单独记录。

## 80 到 110 秒 内部调试

画面：下载 `coremark_debug_ila.sbit`，打开 Fabric Debugger，展示 `coremark_ila` 字段表和实测波形。

旁白：独立 DebugCore 配置使用 192 位、512 点探针，观察退休、写回、Store、Stall、Branch、Flush 和总线握手。诊断配置与正式计分配置分离，因此 ILA 资源不会混入正式 CoreMark 面积和频率数据。

拍摄要求：本段只能使用实体 Fabric Debugger 采集画面。没有实测波形时不得以仿真截图替代。

## 110 到 155 秒 逻辑分析仪现场闭环

画面：J8 上 8 组相邻脚对之间的八根跳线；Python 工具依次切换 counter、UART 和 SPI；波形与 VCD 输出。

旁白：软件通过 13 字节校验包配置模式、数据、速率、触发和前后采样，无需重新综合。Capture Engine 支持八通道、256 点 Raw 缓存、电平与边沿触发，最大内部采样率为 50 MS/s。现场依次改变计数器、UART 和 SPI 数据，核对触发位置、解析字节和导出的 VCD。

## 155 到 175 秒 解耦与复现

画面：Core、Interconnect、UART/GPIO、Logic Analyzer 分层图；四份 bitstream 与 SHA-256 清单。

旁白：最终只交付一套 FPGA 配置：流水线、16 项 BTB、UART/GPIO、性能计数器和八通道逻辑分析仪。发布包保留最终源码、固件、唯一 bitstream、时序报告和 SHA-256，可从统一脚本复核。RLE、Cache 与完整异常中断不在本届范围。

## 175 到 180 秒 收束

画面：作品名称、开发板与最终回归 PASS。

旁白：RISC-V多协议逻辑分析仪，以可验证的处理器为控制核心，完成从采样到协议解析的软硬件闭环。

## 拍摄核对

- 所有屏幕数字与 `release/evidence/automated_metrics.json` 一致。
- CoreMark 仿真估算和实体实测使用不同字幕，不混用。
- PDS ILA 与作品逻辑分析仪分开说明。
- 现场失败不剪掉错误提示；按恢复卡重新连接、下载并复测。
