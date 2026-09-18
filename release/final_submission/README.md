# MES50HP RISC-V 多协议逻辑分析仪最终版

唯一下载文件：`bitstream/mes50hp_riscv_logic_analyzer.sbit`。

PDS 工程文件：`MES50HP_RISCV_Logic_Analyzer.pds`。在 PDS 2024.2-SP2 中直接打开即可查看源码、顶层和约束；需要从头重建时也可在本目录执行 `build_pds.tcl`。

逻辑分析仪使用：下载唯一最终 bitstream，按 J8 相邻脚对接好 8 根杜邦线，然后双击 `启动逻辑分析仪.cmd`。完整操作和故障处理见 `逻辑分析仪使用说明.md`。

- 器件：PGL50H-6IFBG484；系统时钟：50 MHz。
- CPU：RV32I 五级流水线，16 项直接映射 BTB，2-bit 饱和计数器。
- 外设：片上 RAM、CP2102 UART、GPIO、性能计数器、8 通道 Raw 逻辑分析仪。
- J8 回环：3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32。
- 时序：All Constraints Met；慢角 setup WNS +2.812 ns，hold WHS +0.314 ns，估算 Fmax 58.1801 MHz。
- 综合资源：3550 LUT、3136 FF、5.5 个 DRM18K 等效块。
- bitstream SHA-256：17FD57D8F12FF4DCC8FC3A66D644561973E9D75AB9286F09D2F506F94BCDB092。

自动 RTL/软件/PDS 回归均已通过。实体板 JTAG 下载 DONE=1，J8 static/counter/UART/SPI 四模式各 20 次、共 80/80 PASS；证据随包提供。
