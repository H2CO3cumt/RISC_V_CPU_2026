from pathlib import Path
from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_CELL_VERTICAL_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "release" / "materials" / "technical_report.docx"
NAVY = "17365D"
BLUE = "2F5597"
PALE = "EAF0F8"
GRAY = "D9E2F3"


def set_cell_shading(cell, fill):
    tc_pr = cell._tc.get_or_add_tcPr()
    shd = tc_pr.find(qn("w:shd"))
    if shd is None:
        shd = OxmlElement("w:shd")
        tc_pr.append(shd)
    shd.set(qn("w:fill"), fill)


def set_cell_margins(cell, top=90, start=110, bottom=90, end=110):
    tc = cell._tc
    tc_pr = tc.get_or_add_tcPr()
    tc_mar = tc_pr.first_child_found_in("w:tcMar")
    if tc_mar is None:
        tc_mar = OxmlElement("w:tcMar")
        tc_pr.append(tc_mar)
    for key, value in (("top", top), ("start", start), ("bottom", bottom), ("end", end)):
        node = tc_mar.find(qn(f"w:{key}"))
        if node is None:
            node = OxmlElement(f"w:{key}")
            tc_mar.append(node)
        node.set(qn("w:w"), str(value))
        node.set(qn("w:type"), "dxa")


def set_repeat_table_header(row):
    tr_pr = row._tr.get_or_add_trPr()
    tbl_header = OxmlElement("w:tblHeader")
    tbl_header.set(qn("w:val"), "true")
    tr_pr.append(tbl_header)


def add_page_number(paragraph):
    paragraph.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = paragraph.add_run("第 ")
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), "PAGE")
    run._r.addnext(fld)
    paragraph.add_run(" 页")


def apply_font(run, name="DengXian", size=11, bold=False, color=None):
    run.font.name = name
    run._element.get_or_add_rPr().rFonts.set(qn("w:eastAsia"), name)
    run.font.size = Pt(size)
    run.bold = bold
    if color:
        run.font.color.rgb = RGBColor.from_string(color)


def add_paragraph(doc, text, bold_lead=None, align=None):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.25
    if align is not None:
        p.alignment = align
    if bold_lead and text.startswith(bold_lead):
        r1 = p.add_run(bold_lead)
        apply_font(r1, bold=True)
        r2 = p.add_run(text[len(bold_lead):])
        apply_font(r2)
    else:
        r = p.add_run(text)
        apply_font(r)
    return p


def add_bullets(doc, items):
    for item in items:
        p = doc.add_paragraph(style="List Bullet")
        p.paragraph_format.space_after = Pt(3)
        p.paragraph_format.line_spacing = 1.15
        apply_font(p.add_run(item))


def add_table(doc, headers, rows, widths=None):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    table.autofit = False
    set_repeat_table_header(table.rows[0])
    for i, header in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = ""
        set_cell_shading(cell, NAVY)
        set_cell_margins(cell)
        cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        apply_font(p.add_run(str(header)), size=9.5, bold=True, color="FFFFFF")
        if widths:
            cell.width = Inches(widths[i])
    for ridx, row in enumerate(rows):
        cells = table.add_row().cells
        for i, value in enumerate(row):
            cell = cells[i]
            cell.text = ""
            set_cell_margins(cell)
            if ridx % 2 == 1:
                set_cell_shading(cell, "F5F8FC")
            cell.vertical_alignment = WD_CELL_VERTICAL_ALIGNMENT.CENTER
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT if i == 0 else WD_ALIGN_PARAGRAPH.CENTER
            apply_font(p.add_run(str(value)), size=9.2)
            if widths:
                cell.width = Inches(widths[i])
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return table


def add_heading(doc, text, level=1):
    p = doc.add_heading(text, level=level)
    p.paragraph_format.keep_with_next = True
    return p


def page_break(doc):
    doc.add_page_break()


doc = Document()
section = doc.sections[0]
section.page_width = Inches(8.5)
section.page_height = Inches(11)
section.top_margin = Inches(0.72)
section.bottom_margin = Inches(0.7)
section.left_margin = Inches(0.78)
section.right_margin = Inches(0.78)

styles = doc.styles
normal = styles["Normal"]
normal.font.name = "DengXian"
normal._element.rPr.rFonts.set(qn("w:eastAsia"), "DengXian")
normal.font.size = Pt(11)
for name, size, color in (("Title", 26, "000000"), ("Heading 1", 17, "000000"), ("Heading 2", 13, "000000")):
    style = styles[name]
    style.font.name = "DengXian"
    style._element.rPr.rFonts.set(qn("w:eastAsia"), "DengXian")
    style.font.size = Pt(size)
    style.font.color.rgb = RGBColor.from_string(color)
    style.font.bold = True

footer = section.footer.paragraphs[0]
add_page_number(footer)
for run in footer.runs:
    apply_font(run, size=9, color="666666")

# Cover
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_before = Pt(85)
r = p.add_run("RISC-V多协议逻辑分析仪")
apply_font(r, size=28, bold=True)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = p.add_run("基于 MES50HP 的 RV32I 五级流水线 CPU 与八通道采集平台")
apply_font(r, size=15, color=BLUE)
p.paragraph_format.space_after = Pt(42)
add_table(doc, ["项目", "当前交付状态"], [
    ["处理器", "RV32I 单周期参考模型与五级流水线，自动回归 PASS"],
    ["FPGA", "PGL50H-6IFBG484，50 MHz，唯一最终 bitstream 已生成"],
    ["应用", "8 通道 Raw 逻辑分析仪，UART/SPI 软件解析与 VCD 输出"],
    ["版本", "competition final candidate，J8 实体闭环 80/80 PASS"],
], [1.8, 4.8])
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_before = Pt(38)
apply_font(p.add_run("2026 全国大学生嵌入式芯片与系统设计竞赛\n紫光同创 FPGA 创新设计赛道"), size=13)
p = doc.add_paragraph()
p.alignment = WD_ALIGN_PARAGRAPH.CENTER
p.paragraph_format.space_before = Pt(24)
apply_font(p.add_run("技术报告候选版  2026 年 9 月 17 日"), size=11, color="666666")

page_break(doc)
add_heading(doc, "摘要", 1)
add_paragraph(doc, "本项目在盘古 50 MES50HP 开发板上实现支持 RV32I 的处理器系统。开发过程先冻结单周期 CPU 作为架构参考，再实现 IF、ID、EX、MEM、WB 五级流水线，并加入数据前递、Load-Use 暂停、Branch/Jump 冲刷、随机背压与 Reset 中止处理。CPU Core 只通过统一取指事务、数据事务、提交 trace 和性能事件连接外部系统，RAM、UART、GPIO、地址译码、性能计数器与逻辑分析仪均位于 Core 外部。")
add_paragraph(doc, "当前自动化回归覆盖完整 RV32I 定向测试、上游 RV32UI Core 29 项与 Memory 10 项、GCC 裸机程序、Single Cycle 与 Pipeline 的完整退休 trace、官方 CoreMark CRC、逻辑分析仪采集与 Python/VCD 工具。唯一最终 MES50HP 配置已生成 bitstream 并通过 50 MHz 时序约束。同一 CoreMark 镜像的 Predictor Off/On 对比中，On 的 CPI 为 2.3747，并减少 12.06% 周期；这些数值不替代实体板跑分。")
add_paragraph(doc, "应用端提供八通道、256 点 Raw 缓存、可调采样分频、电平/上升沿/下降沿触发和触发前后采样。RISC-V 软件使用 MMIO 配置 Capture Engine，解析 UART/SPI 并通过 115200 8N1 串口发送样本，Python 工具复核协议并输出 VCD。软件、RTL、固件和约束已经收口；MES50HP JTAG 下载 DONE=1，J8 static、counter、UART 和 SPI 四模式各 20 次，共 80/80 实体闭环 PASS。")
add_heading(doc, "关键词", 2)
add_paragraph(doc, "RISC-V  RV32I  五级流水线  FPGA  CoreMark  MMIO  逻辑分析仪")

page_break(doc)
add_heading(doc, "1 项目目标与范围", 1)
add_paragraph(doc, "作品以完整、可验证的 RV32I 处理器为主线，以可重构逻辑分析仪证明软硬件协同和 Core 外设解耦。竞赛版本固定使用 MES50HP、50 MHz 和片上 RAM，不实现 Cache、burst、完整异常中断、AI、外部 DDR、HDMI、PCIe、千兆网或自定义指令。最终流水线加入经过 Predictor Off/On 对比验证的 16 项 BTB；RLE 仍冻结为赛后研究。")
add_table(doc, ["交付主线", "实现内容", "验收证据"], [
    ["ISA 与 Reference", "RV32I 单周期 CPU", "定向测试、RV32UI、GCC、提交 trace"],
    ["流水线", "五级数据通路与 Hazard", "固定/随机背压、Reset、Reference 对比"],
    ["性能", "计数器与官方 CoreMark", "CRC、CPI、PDS Timing/Resource"],
    ["应用", "8 通道 Raw 分析仪", "独立 TB、SoC、Python/VCD、板级脚本"],
    ["发布", "唯一最终 FPGA 配置", "bitstream、报告、固件、SHA-256"],
], [1.35, 2.25, 3.0])
add_heading(doc, "证据口径", 2)
add_bullets(doc, [
    "RTL 仿真估算用于说明架构性能和官方 CRC，不写成实体跑分。",
    "PDS 数字来自综合、布局布线和时序报告，统一注明目标器件与 50 MHz 约束。",
    "实体结论只接受板卡脚本、串口日志、Fabric Debugger 波形和断电复测记录。",
])

page_break(doc)
add_heading(doc, "2 系统架构", 1)
add_table(doc, ["层级", "职责", "边界"], [
    ["Pipeline Core", "RV32I 执行、流水级、Hazard、事务发起", "不含设备地址和设备专用端口"],
    ["SoC Interconnect", "RAM/MMIO 译码与唯一响应汇合", "统一 valid/ready 请求响应"],
    ["基础外设", "UART TX/RX、GPIO、性能计数器", "Core 外部 MMIO 从设备"],
    ["应用外设", "Capture Engine、触发、BRAM、pattern generator", "Application MMIO 子窗口"],
    ["Board Wrapper", "时钟、Reset、I/O 极性和 MES50HP 引脚", "PDS .fdc 与板级顶层"],
], [1.35, 2.8, 2.45])
add_paragraph(doc, "取指端口和数据端口均采用单 outstanding 的 request/response 握手。请求只有在 valid 与 ready 同时为 1 时接受；等待期间地址、写数据与字节使能保持稳定。每个已接受事务产生且只产生一次响应，写副作用恰好发生一次。该契约使低速 UART、逻辑分析仪 MMIO 和同步 BRAM 都能通过背压接入，而不向 Core 增加 busy 或 done 信号。")
add_heading(doc, "地址映射", 2)
add_table(doc, ["区域", "地址", "用途"], [
    ["RAM", "0x00000000 起", "程序与数据，配置按 SoC 参数确定"],
    ["UART", "0x10000000", "TXDATA、STATUS、RXDATA"],
    ["GPIO", "0x10001000", "LED 与输入寄存器"],
    ["Performance", "0x10002000..0x100020FF", "十项 64-bit 计数器"],
    ["Logic Analyzer", "0x10002100..0x100021FF", "配置、状态与 Raw 读取"],
], [1.45, 2.45, 2.7])

page_break(doc)
add_heading(doc, "3 RV32I 单周期参考模型", 1)
add_paragraph(doc, "单周期 CPU 先完成寄存器堆、ALU、立即数生成、译码、分支比较、Load/Store 数据整理和行为级 IMEM/DMEM，再迁移到统一事务接口。Reference Model 输出退休 trace，包括 valid、PC、instruction、寄存器写回与 Store 地址、数据和字节使能。")
add_table(doc, ["指令类别", "支持范围", "边界策略"], [
    ["整数运算", "全部 RV32I R/I ALU、LUI、AUIPC", "x0 永远为零"],
    ["Load", "LB、LBU、LH、LHU、LW", "自然对齐，非对齐无副作用"],
    ["Store", "SB、SH、SW", "byte-enable，非对齐禁止写"],
    ["控制流", "六类 Branch、JAL、JALR", "JALR target bit 0 清零"],
    ["系统边界", "FENCE 保守 no-op", "FENCE.I/SYSTEM/CSR 非法且无副作用"],
], [1.35, 2.85, 2.4])
add_paragraph(doc, "上游 riscv-tests 固定版本中的 RV32UI Core 29 项和 Memory 10 项全部通过。两项 GCC 裸机程序覆盖启动栈、函数调用、循环、data/bss 与分支控制。Task 17 的正式 Reference Regression 汇总 14 个入口，支持故意篡改 rd_data 或 mem_data 后报告首个不同字段。")

page_break(doc)
add_heading(doc, "4 五级流水线与控制", 1)
add_table(doc, ["流水级", "主要工作", "关键状态"], [
    ["IF", "发起取指并接收响应", "PC、请求 epoch、错误路径丢弃"],
    ["ID", "译码与寄存器读取", "源寄存器使用位、立即数、控制信号"],
    ["EX", "ALU、分支、前递选择", "redirect、load-use 检测"],
    ["MEM", "数据事务与等待", "请求字段稳定、一次副作用"],
    ["WB", "寄存器写回与退休", "trace 与性能事件"],
], [1.05, 2.8, 2.75])
add_heading(doc, "Hazard 处理", 2)
add_bullets(doc, [
    "Forwarding 选择 EX/MEM 为最高优先级，MEM/WB 为次优先级；Load、x0、无效或错误写回被排除。",
    "Load-Use 相关冻结 PC 与 IF/ID，并向 ID/EX 注入 Bubble；Store 和 Branch 的两个源操作数均参与检测。",
    "Branch、JAL 和 JALR 在 EX 级重定向并冲刷错误路径。被冲刷指令不得写 RegFile、RAM、MMIO 或提交 trace。",
    "数据事务等待期间保持流水线状态，WB 值继续可前递；定向用例 `wb_hold` 覆盖该边界。",
])
add_paragraph(doc, "Task 23 汇总 10 个入口，覆盖一级/二级前递、同 rd 优先级、Load 到 ALU/Store/Branch、taken 与 not-taken、JAL/JALR、错误响应、随机背压和 Reset 中止。所有测试按退休顺序与 Reference Model 比较。")

page_break(doc)
add_heading(doc, "5 验证体系", 1)
add_table(doc, ["层次", "验证内容", "当前结果"], [
    ["模块", "RegFile、ALU、ImmGen、Decoder、Branch、Load/Store", "全部独立 PASS"],
    ["ISA", "RV32UI Core 29 项、Memory 10 项", "全部 PASS"],
    ["Reference", "14 个系统入口、首差检测", "14 passed 0 failed"],
    ["Pipeline", "10 个 Hazard/背压/Reset/Trace 入口", "全部 PASS"],
    ["GCC", "c_smoke 与 array_control，固定/随机延迟", "trace 与状态一致"],
    ["Application", "采集、MMIO、SoC、UART 协议、Python/VCD", "自动化全部 PASS"],
    ["Release", "范围审计、唯一最终 bitstream、SHA-256", "自动化 PASS"],
], [1.15, 3.3, 2.15])
add_paragraph(doc, "Debug 原则固定为沿 IF、ID、EX、MEM、WB 查找第一个错误周期和第一个错误信号。提交级比较优先于最终状态比较，因为它能够区分前递选择错误、错误路径提交、写回时机错误和 Store 数据错误。")
add_heading(doc, "最终自动化入口", 2)
add_paragraph(doc, "`scripts/run_final_regression.ps1` 先运行 RV32I 与历史 Reference，再运行 Pipeline、GCC、性能计数器、CoreMark、应用和范围审计，最后核对唯一最终 bitstream 的存在性、长度与 SHA-256。Quick 模式跳过长 CoreMark 仿真，但不跳过其他安全检查。")

page_break(doc)
add_heading(doc, "6 CoreMark 与性能结果", 1)
add_paragraph(doc, "官方 EEMBC CoreMark checkout 固定到提交 1f483d5b8316753a742cbf5590caf5bd0a4e4777。编译目标为 `-march=rv32i -mabi=ilp32`。fixed latency、random backpressure 和同步 FPGA memory model 均输出官方 CRC；正式镜像为 1000 iterations，串口收到 R 后启动。")
add_table(doc, ["指标", "当前值", "证据类型"], [
    ["ticks/iteration", "1,923,077", "RTL FPGA memory model"],
    ["Cycles", "2,042,520", "RTL 仿真计数器"],
    ["Predictor On cycles", "1,852,156", "RTL 仿真计数器"],
    ["Predictor On Instret", "779,952", "RTL 仿真计数器"],
    ["Predictor On CPI", "2.3747", "Cycles / Instret"],
    ["Predictor cycle reduction", "12.06%", "同一镜像相对 Predictor Off"],
], [2.0, 2.05, 2.55])
add_table(doc, ["配置", "LUT", "FF", "DRM", "Setup WNS", "Hold WNS", "估算 Fmax"], [
    ["唯一最终版", "3459", "3129", "5.5", "+2.661 ns", "+0.312 ns", "57.6735 MHz"],
], [1.25, .62, .62, .55, .9, .9, 1.05])
add_paragraph(doc, "资源与时序数字来自唯一最终 PDS 构建；CoreMark 性能来自同一流水线 RTL 的官方 CRC 仿真。二者均可自动复核，但不合并冒充实体板 CoreMark/LUT 成绩。")

page_break(doc)
add_heading(doc, "7 性能计数器与 PDS DebugCore", 1)
add_paragraph(doc, "Core 外部 `perf_monitor` 统计 cycle、instret、stall、load stall、branch、branch taken、flush、predict、BTB hit 和 misprediction 十项 64-bit 计数器，并通过 MMIO 读取。计数器只消费通用事件，不改变流水线端口。")
add_table(doc, ["DebugCore 位段", "信号"], [
    ["0", "retired instruction valid"],
    ["32:1 / 64:33", "retired PC / instruction"],
    ["65 / 70:66 / 102:71", "register write enable / rd / data"],
    ["103 / 135:104 / 167:136 / 171:168", "Store valid / address / data / strobes"],
    ["172..176", "stall / load stall / branch / taken / flush"],
    ["177..182", "reset 与取指/数据握手、memory ready"],
], [2.5, 4.1])
add_paragraph(doc, "开发阶段的 DebugCore 用于观察退休、Branch 与 Flush，但不作为第二套交付配置。MES50HP 已完成最终位流下载和 J8 四模式 80/80 实体回环；Fabric Debugger 内部波形仍只在取得真实截图后陈述。最终包使用十项性能计数器保留可重复的量化证据。")

page_break(doc)
add_heading(doc, "8 可重构多协议逻辑分析仪", 1)
add_table(doc, ["能力", "实现"], [
    ["通道与深度", "8 通道，256 samples Raw 缓存"],
    ["采样", "sample_div 可调，50 MHz 时 sample_div=0 对应 50 MS/s"],
    ["触发", "电平、上升沿、下降沿，通道掩码与触发值可编程"],
    ["窗口", "精确 pre + trigger + post，trigger index 为 Raw 逻辑索引"],
    ["激励", "static、counter、UART 8N1、SPI mode 0"],
    ["软件", "RV32I MMIO 驱动、UART/SPI 解析、Python 复核与 VCD"],
], [1.6, 5.0])
add_paragraph(doc, "正式固件上电发送 `LA_READY`，随后接收 13 字节配置包。包内包含 mode、data、pattern divider、sample divider、trigger type、mask、value、pre、post 和 XOR checksum。每次采集输出 Raw count、trigger index、样本、协议解析结果与 `LA_DONE`，完成后重新发送 `LA_READY`。")
add_table(doc, ["量化指标", "当前值", "边界"], [
    ["触发延迟", "0 个额外 sample tick", "命中样本同拍成为 trigger sample"],
    ["UART 线路速率", "115200 bit/s", "8N1，有效上限 11520 B/s"],
    ["256 点文本上传", "约 0.20 s", "约 9 B/sample 的线路估算"],
    ["自动化连续压力", "20/20 PASS", "每五轮 Reset"],
    ["实体 J8 回环", "80/80 PASS", "static、counter、UART、SPI 各 20 次"],
], [1.9, 1.7, 3.0])

page_break(doc)
add_heading(doc, "9 FPGA 平台与发布配置", 1)
add_table(doc, ["项目", "冻结值"], [
    ["开发板与器件", "盘古 50 MES50HP，PGL50H-6IFBG484"],
    ["时钟", "P20，50 MHz，20.000 ns"],
    ["UART", "RX=R8，TX=R9，115200 8N1"],
    ["Reset", "默认内部上电复位；REST 用于重新加载固件"],
    ["采集输入", "J8-4,8,12,16,20,24,28,32"],
    ["激励输出", "J8-3,7,11,15,19,23,27,31；逐位连接隔行相邻输入脚"],
], [2.0, 4.6])
add_table(doc, ["文件", "用途", "验收口径"], [
    ["mes50hp_riscv_logic_analyzer.sbit", "唯一最终下载文件", "完整 CPU 与逻辑分析仪应用"],
], [2.45, 2.35, 1.8])
add_paragraph(doc, "`release/SHA256SUMS.txt` 覆盖源码、测试、PDS 证据和交付物，`release/build_manifest.txt` 记录 Git、CoreMark 提交、Pipeline Core 哈希、工具版本、器件与时钟。任何 RTL 或软件修改都必须重跑最终回归并重建清单。")

page_break(doc)
add_heading(doc, "10 复现与实体验收", 1)
add_paragraph(doc, "自动化构建从仓库根目录运行 `scripts/build_competition_release.ps1`。在已有 PDS 产物时可使用 `-SkipPds`；完整构建通过 `-LicenseFile` 或 `PANGO_LICENSE_FILE` 提供本机许可证。脚本不复制许可证，也不把实体结果从仿真推导出来。")
add_heading(doc, "实体板验收状态", 2)
add_bullets(doc, [
    "CoreMark 的官方 CRC、Predictor Off/On 和十项计数器由自动 RTL 回归复核；唯一最终 bitstream 用于完整逻辑分析仪应用演示。",
    "J8-3↔4、7↔8、11↔12、15↔16、19↔20、23↔24、27↔28、31↔32 已完成实体回环，四种模式各 20 次，UART、JSON 和 VCD 已归档。",
    "完成三轮断电五秒、重新供电、重新下载与复测，分别保存到 run01、run02、run03。",
])
add_heading(doc, "失败处理", 2)
add_paragraph(doc, "任一脚本没有输出 PASS 时停止冻结，保留原始日志并定位第一个失败点。现场只允许重新连接、重新下载同一 SHA-256 bitstream、重启串口和按恢复卡复测；不得临时改 RTL、接口、采样协议或性能数字。")

page_break(doc)
add_heading(doc, "11 当前限制与后续工作", 1)
add_table(doc, ["项目", "当前状态", "进入 competition final 的条件"], [
    ["实体 CoreMark", "未采集", "串口脚本 PASS，计时不少于 10 秒"],
    ["物理回环", "80/80 PASS", "实体数据、协议解析与 VCD 已归档"],
    ["断电压力", "未执行", "三轮断电、下载、Reset 与演示一致"],
    ["报告/PPT/视频", "候选材料已生成", "替换待补证位置并核对同一清单"],
], [1.45, 1.65, 3.2])
add_paragraph(doc, "项目目前满足自动化 Regression、PDS 发布和 G11 物理回环条件。实体 CoreMark、Fabric Debugger 波形、断电压力和最终视频仍按独立证据出口管理，因此版本保持 `competition_final_candidate`。这些项目不需要修改 CPU、外设 RTL、软件协议或 J8 约束。")
add_heading(doc, "结论", 1)
add_paragraph(doc, "本项目完成了可由自动化证据追踪的 RV32I 单周期参考模型、五级流水线 Core、基础 SoC、官方 CoreMark 集成和八通道逻辑分析仪应用。统一事务接口与提交级比较把 CPU 正确性、外设扩展和性能分析连接成同一验证链。MES50HP J8 四模式实体回环已连续 80 次通过，剩余证据仅限 CoreMark 实体计分、内部调试波形、断电复测与视频素材。")

OUT.parent.mkdir(parents=True, exist_ok=True)
doc.save(OUT)
print(f"WROTE {OUT}")
