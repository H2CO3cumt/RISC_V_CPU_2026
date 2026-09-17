# 现场恢复卡

## 固定条件

- 板卡：MES50HP，器件 `PGL50H-6IFBG484`
- 时钟：P20，50 MHz
- 串口：CP2102，115200 8N1，无流控，RX=R8，TX=R9
- Reset：默认内部上电复位；`REST` 用于重新加载配置
- 逻辑分析仪跳线：J8-3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32，并共地

## 五分钟恢复顺序

1. 断电，检查 USB-JTAG、独立 CP2102 数据线和跳线方向。
2. 上电，在 PDS Programmer 中确认器件型号。
3. 按演示目标下载对应 bitstream，并核对 `release/SHA256SUMS.txt`。
4. 关闭其他占用串口的软件，确认 COM 号与 115200 8N1。
5. 运行对应脚本；脚本未输出 PASS 时停止演示，保存原始日志。

## Bitstream 选择

| 目标 | 文件 | 预期首个现象 |
|---|---|---|
| 基础流水线 | `pipeline_soc.sbit` | LED/UART 基础程序运行 |
| CoreMark 正式 | `coremark_stable.sbit` | UART 输出 READY |
| CoreMark ILA | `coremark_debug_ila.sbit` | Fabric Debugger 可见 `coremark_ila` |
| 逻辑分析仪 | `logic_analyzer_p0.sbit` | LED=0x5A，UART 输出 LA_READY |

## CoreMark 无输出

1. 确认下载的是 `coremark_stable.sbit`。
2. 重新插拔独立 CP2102 数据线并重开串口。
3. 等待 READY 后发送大写 `R`。
4. 仍无输出时按 `REST` 重新加载；不要改 RTL 或串口参数。

## Fabric Debugger 无波形

1. 确认下载的是 `coremark_debug_ila.sbit`。
2. 重新扫描 JTAG 链并选择 `coremark_ila`。
3. 先用 bit 0 的退休事件触发；需要控制流证据时再用 bit 174/176。
4. 仍无法采集时保存界面与日志，切回正式 CoreMark 演示，不声称 ILA 已实测。

## 逻辑分析仪超时或解析错误

1. 逐位检查 J8 的 8 组隔行相邻脚对（3↔4 至 31↔32），确认 GND 共地；不要使用 J8-2（5V）。
2. 等待 `LA_READY` 后再发送下一配置包。
3. 先运行 static，再运行 counter，最后运行 UART/SPI。
4. 重新下载同一 bitstream 后复测；不要临时改采样深度、触发协议或固件。

## 证据保存

- 每轮保存 UART 原始日志、JSON、VCD、PDS/Fabric Debugger 截图和 bitstream SHA-256。
- 三轮断电测试分别写入 `release/evidence/board/run01`、`run02`、`run03`。
- 失败结果保留，修复后另建新一轮目录，不覆盖原记录。
