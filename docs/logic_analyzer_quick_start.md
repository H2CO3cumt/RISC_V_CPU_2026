# MES50HP 逻辑分析仪使用说明

## 一次完成的使用顺序

1. 关闭开发板电源后，用 8 根杜邦线连接 J8：`3↔4`、`7↔8`、`11↔12`、`15↔16`、`19↔20`、`23↔24`、`27↔28`、`31↔32`。
2. 给开发板上电并连接板载 CP2102 USB 串口。
3. 在 PDS Programmer 中下载 `bitstream/mes50hp_riscv_logic_analyzer.sbit`。
4. 双击最终包根目录的 `启动逻辑分析仪.cmd`。
5. 在“板载 CP2102 串口”中选择名称包含 `Silicon Labs` 或 `CP210x` 的 COM 口，保持 `115200`，首次测试把“Runs/模式”设为 `1`。
6. 点击“采集四种模式并生成 VCD”。窗口依次测试 static、counter、UART 和 SPI；全部完成后应显示 `逻辑分析仪四模式 PASS`。
7. 点击“打开输出目录”。每种模式都有原始 `.log`、波形 `.vcd` 和汇总 `summary.json`；VCD 可用 GTKWave 打开。

## 四种模式的作用

- `static`：固定电平，先确认接线和通道映射。
- `counter`：连续变化的 8 位计数，用于确认八通道都能采样。
- `uart`：生成并采集 UART 8N1 波形，软件自动还原测试字节。
- `spi`：生成并采集 SPI mode 0 波形，软件自动还原测试字节。

## 正常现象

- 下载后串口会出现 `LA_READY`。
- 每次采集会收到 `LA_DONE`，随后再次收到 `LA_READY`。
- 日志中每轮出现 `LOGIC ANALYZER BOARD RUN ... PASS`。

## 常见失败

- 出现 `No module named coremark_serial`：打开了旧版四配置验证工具。请关闭它，只运行最终包中的 `启动逻辑分析仪.cmd`。
- 一直等不到 `LA_READY`：通常是下载了旧 bitstream、选错 COM 口，或下载后没有重新复位。重新下载最终 `.sbit`，再刷新并选择 CP210x 串口。
- 串口被占用：关闭 PDS 串口终端、串口助手和其他验证窗口后重试。
- static 能通过但 UART/SPI 失败：检查八组 J8 相邻脚是否全部接牢，不要跨接到 J11/J12。
- 提示缺少 `serial`：在最终包目录执行 `py -3 -m pip install -r tools\pyUI_requirements.txt`。

最终版不再使用 `logic_analyzer_p0.sbit`、`coremark_stable.sbit` 或旧版 `MES50HP Board Validation` 界面。
