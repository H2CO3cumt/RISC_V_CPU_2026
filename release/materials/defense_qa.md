# 答辩问答稿

## 为什么先做单周期 CPU

单周期 CPU 提供简单、稳定的架构参考。流水线与它运行同一程序后，自动比较 x1 至 x31、关键 RAM 和退休 trace。若结果不同，比较器报告第一条不一致提交以及具体字段，定位比只看最终状态更直接。

## 五级流水线如何处理数据冒险

EX 级优先使用 EX/MEM 结果，其次使用 MEM/WB 结果；x0、无效写回和出错响应不参与前递。Load 数据在 EX/MEM 阶段尚未可用，因此紧邻使用者触发 Load-Use Stall，冻结前端并向 ID/EX 注入 Bubble。数据事务整体等待期间，WB 值必须继续可前递，这一点有独立定向用例覆盖。

## 分支和跳转如何保证错误路径没有副作用

Branch、JAL 和 JALR 在 EX 级确定重定向。Redirect 冲刷 IF/ID 与 ID/EX 的错误路径指令。被冲刷指令不得进入 Store 请求、寄存器写回或退休 trace；已展示但尚未接受的取指请求按握手协议完成后丢弃其响应。

## Core 与外设如何解耦

`pipeline_cpu` 只暴露取指事务、数据事务、提交 trace 和通用性能事件。RAM、地址译码、UART、GPIO、逻辑分析仪和板级引脚都位于 Core 外。最终只交付一套完整配置，范围审计同时检查 Core 中不存在设备地址或设备专用端口。

## 为什么 CoreMark 数字分为仿真估算和实体实测

当前官方 CoreMark 在 fixed、random 和同步 FPGA memory model 下通过官方 CRC。由仿真 tick 推得 CoreMark/MHz=0.520000，属于 RTL 仿真估算。PDS 给出的 68.2594 MHz、LUT、FF 和 DRM 属于布局布线结果。实体板运行时间、分数与稳定性必须由串口脚本采集，不能从仿真推断。

## CPI 2.6682 的主要来源是什么

同步片上存储模型、取指与数据事务等待、Load-Use 相关和控制流冲刷共同增加周期。当前仿真记录 2,042,520 cycles 与 765,519 retired instructions，对应 CPI 2.6682；性能计数器同时记录 stall、load stall、branch、taken 和 flush，便于在 ILA 中对照关键循环。

## PDS ILA 和作品逻辑分析仪有什么区别

PDS DebugCore 观察 CPU 内部退休、流水控制和握手信号，用于性能诊断。作品逻辑分析仪是 Core 外部 MMIO 外设，采集板外八路数字信号并由 RISC-V 软件解析 UART/SPI。二者的对象、资源配置与演示目标不同。

## 为什么正式 CoreMark bitstream 不含 DebugCore

DebugCore 消耗额外逻辑和存储资源，也可能改变关键路径。项目将正式计分配置与诊断配置分开，正式资源/Fmax 使用 `coremark_stable.sbit`，内部波形使用 `coremark_debug_ila.sbit`。这样可以保持性能指标口径一致。

## 逻辑分析仪为什么选择 Raw 而没有实现 RLE

本届优先保证 RV32I、流水线、CoreMark、Timing 和实体闭环的正确性与可复现性。Raw 模式已经覆盖 8 通道、前后触发、256 点缓存、UART/SPI 软件解析和 VCD。RLE 会增加编码、溢出和解码验证范围，因此冻结为赛后研究，不进入本届发布。

## 为什么实现 BTB 但不宣称完成高级控制逻辑

最终版本实现了 16 项直接映射 BTB 与 2-bit 饱和计数器，并用 Predictor Off/On、别名替换、错误恢复和 CoreMark 数据验证。官方高级控制逻辑还要求完整异常/中断，因此本项目只陈述“实现动态分支预测”，不把 BTB 单项包装成完整高级控制逻辑；Cache 与完整异常/中断仍不在本届范围。

## 当前还缺哪些证据

自动化回归和唯一最终 PDS 构建已完成。最终位流已下载到 MES50HP，J8 static、counter、UART 和 SPI 各连续 20 次，共 80/80 实体回环 PASS；UART 20 次均解码 `A5` 且无帧错误，SPI 20 次均解码 `3C`。CoreMark 实体成绩和 Fabric Debugger 波形仍只按各自真实证据陈述。
