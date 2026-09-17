import fs from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { Presentation, PresentationFile } from "@oai/artifact-tool";

const ROOT = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/(?:[A-Za-z]:)/, m => m.slice(1))), "..");
const SKILL_DIR = "C:/Users/xwc/.codex/plugins/cache/openai-primary-runtime/presentations/26.905.11957/skills/presentations";
const RUNTIME_PYTHON = "C:/Users/xwc/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe";
const TMP_DIR = path.join(ROOT, "tmp", "defense_deck");
const OUT_DIR = path.join(ROOT, "release", "materials");
const FINAL_PPTX = path.join(OUT_DIR, "defense_presentation.pptx");
await fs.mkdir(TMP_DIR, { recursive: true });
await fs.mkdir(OUT_DIR, { recursive: true });

const { applyPresentationChartFont, finalizePresentation } = await import(
  pathToFileURL(path.join(SKILL_DIR, "container_tools", "artifact_tool_utils.mjs")).href
);

const font = "SimHei";
const navy = "#17365D";
const blue = "#2F5597";
const cyan = "#2A9D8F";
const orange = "#E07A5F";
const pale = "#EAF0F8";
const gray = "#667085";
const light = "#F6F8FB";
const white = "#FFFFFF";
const black = "#111827";

const deck = Presentation.create({ slideSize: { width: 1280, height: 720 } });

function box(slide, x, y, w, h, fill = "none", line = "none", radius = 0) {
  return slide.shapes.add({
    geometry: radius ? "roundRect" : "rect",
    position: { left: x, top: y, width: w, height: h },
    fill,
    line: { fill: line, width: line === "none" ? 0 : 1.2 },
  });
}

function text(slide, value, x, y, w, h, size = 24, opts = {}) {
  const s = slide.shapes.add({
    geometry: "textbox",
    position: { left: x, top: y, width: w, height: h },
    fill: "none",
    line: { fill: "none", width: 0 },
  });
  s.text = value;
  s.text.style = {
    typeface: font,
    fontSize: size,
    bold: opts.bold ?? false,
    color: opts.color ?? black,
    alignment: opts.align ?? "left",
    verticalAlignment: opts.vAlign ?? "middle",
    autoFit: "shrinkText",
  };
  return s;
}

function title(slide, value, sub = "") {
  text(slide, value, 68, 34, 1140, 58, 34, { bold: true, color: navy });
  if (sub) text(slide, sub, 70, 92, 1120, 34, 16, { color: gray });
  box(slide, 68, 128, 1140, 3, blue, "none");
}

function footer(slide, n, evidence = "") {
  text(slide, `RISC-V多协议逻辑分析仪   ${String(n).padStart(2, "0")}`, 70, 680, 390, 22, 13, { color: gray });
  if (evidence) text(slide, evidence, 710, 680, 500, 22, 12, { color: gray, align: "right" });
}

function note(slide, value) {
  slide.speakerNotes.textFrame.setText(value);
}

function stage(slide, label, detail, x, color) {
  box(slide, x, 240, 188, 150, white, color, 10);
  box(slide, x, 240, 188, 42, color, "none", 10);
  text(slide, label, x, 240, 188, 42, 24, { bold: true, color: white, align: "center" });
  text(slide, detail, x + 13, 292, 162, 85, 18, { align: "center" });
}

function applyTableStyle(table, rows, cols, widths = []) {
  table.borders.assign({ style: "solid", fill: "#D9D9D9", width: 1 });
  for (let c = 0; c < cols; c++) {
    table.getCell(0, c).fill = navy;
    table.getCell(0, c).text.style = { typeface: font, fontSize: 18, bold: true, color: white, alignment: "center" };
  }
  for (let r = 1; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      if (r % 2 === 0) table.getCell(r, c).fill = "#F3F6FA";
      table.getCell(r, c).text.style = { typeface: font, fontSize: 16, color: black, alignment: c === 0 ? "left" : "center" };
    }
  }
  widths.forEach((w, i) => { table.columns.get(i).width = w; });
}

// 1 Cover
{
  const s = deck.slides.add();
  s.background.fill = white;
  box(s, 0, 0, 1280, 720, white, "none");
  box(s, 0, 0, 24, 720, navy, "none");
  text(s, "RISC-V多协议逻辑分析仪", 90, 132, 1080, 92, 52, { bold: true, color: navy });
  text(s, "RV32I 五级流水线 CPU 与八通道采集平台", 94, 235, 960, 48, 27, { color: blue });
  box(s, 94, 324, 1000, 2, blue, "none");
  text(s, "MES50HP  PGL50H-6IFBG484  50 MHz", 94, 354, 1000, 42, 21, { color: black });
  text(s, "技术答辩候选稿", 94, 448, 400, 42, 20, { bold: true, color: orange });
  text(s, "自动化回归与 PDS 已完成\n实体板最终证据待补", 94, 500, 600, 84, 21, { color: gray });
  text(s, "2026", 1025, 558, 150, 72, 46, { bold: true, color: pale, align: "right" });
  note(s, "来源：docs/progress.md；release/evidence/automated_metrics.json。当前版本为 competition_final_candidate。");
}

// 2 Scope
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "交付范围", "主线聚焦正确性、性能和可复现应用");
  const rows = [
    ["处理器", "完整 RV32I 与五级流水线", cyan],
    ["性能", "官方 CoreMark、计数器与 PDS Timing", blue],
    ["应用", "8 通道 Raw、UART/SPI、Python/VCD", orange],
    ["发布", "唯一最终 bitstream、报告、固件和 SHA-256", navy],
  ];
  rows.forEach((r, i) => {
    const y = 172 + i * 100;
    box(s, 92, y, 170, 70, r[2], "none", 8);
    text(s, r[0], 92, y, 170, 70, 23, { bold: true, color: white, align: "center" });
    text(s, r[1], 292, y, 850, 70, 23, { color: black });
  });
  text(s, "冻结项", 92, 594, 140, 34, 18, { bold: true, color: gray });
  text(s, "RLE、Cache、完整异常中断、AI、DDR、HDMI、PCIe、千兆网、自定义指令", 222, 588, 930, 48, 17, { color: gray });
  footer(s, 2, "范围依据 docs/roadmap.md");
  note(s, "来源：AGENTS.md；docs/roadmap.md；docs/competition_scoring.md。");
}

// 3 Architecture
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "Core 与 SoC 边界", "外设变化不修改 pipeline_cpu");
  box(s, 82, 190, 320, 350, pale, blue, 14);
  text(s, "Pipeline Core", 105, 210, 274, 54, 28, { bold: true, color: navy, align: "center" });
  text(s, "RV32I 执行\nIF ID EX MEM WB\nForwarding  Stall  Flush", 112, 286, 260, 150, 22, { align: "center" });
  text(s, "统一事务 + trace + 性能事件", 112, 466, 260, 42, 17, { color: gray, align: "center" });
  box(s, 480, 190, 220, 350, white, cyan, 14);
  text(s, "Interconnect", 500, 216, 180, 44, 26, { bold: true, color: cyan, align: "center" });
  text(s, "RAM/MMIO 译码\n唯一响应汇合\nvalid/ready 背压", 504, 300, 172, 134, 21, { align: "center" });
  const per = [["RAM", 760, 190], ["UART/GPIO", 990, 190], ["Performance", 760, 370], ["Logic Analyzer", 990, 370]];
  per.forEach(([label, x, y], i) => { box(s, x, y, 190, 130, i < 2 ? light : pale, i < 2 ? gray : blue, 10); text(s, label, x + 10, y + 20, 170, 90, 22, { bold: true, color: i < 2 ? black : navy, align: "center" }); });
  box(s, 402, 357, 78, 4, blue, "none"); box(s, 700, 357, 60, 4, cyan, "none"); box(s, 940, 252, 50, 4, gray, "none"); box(s, 940, 432, 50, 4, blue, "none");
  text(s, "Core 中不存在设备地址、片选和 UART/GPIO/分析仪专用端口", 84, 582, 1095, 44, 21, { bold: true, color: orange, align: "center" });
  footer(s, 3, "接口契约 docs/interfaces.md");
  note(s, "来源：docs/interfaces.md。图中所有外设与地址译码均位于 Core 外部。");
}

// 4 Pipeline stages
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "五级流水线", "控制流在 EX 重定向，事务在 MEM 等待，退休在 WB 输出");
  stage(s, "IF", "取指请求\nPC 与错误响应丢弃", 74, navy);
  stage(s, "ID", "译码\n寄存器读取", 276, blue);
  stage(s, "EX", "ALU 与 Branch\n前递选择", 478, cyan);
  stage(s, "MEM", "Load Store\n背压等待", 680, orange);
  stage(s, "WB", "写回\n提交 trace", 882, navy);
  for (const x of [262, 464, 666, 868]) box(s, x, 312, 14, 4, gray, "none");
  box(s, 1080, 240, 120, 150, light, gray, 10);
  text(s, "外部存储\n与 MMIO", 1087, 266, 106, 100, 16, { align: "center" });
  box(s, 1058, 312, 22, 4, gray, "none");
  text(s, "关键约束", 90, 465, 170, 42, 22, { bold: true, color: navy });
  text(s, "请求等待期间字段稳定   错误路径无副作用   每条指令最多退休一次", 92, 520, 1080, 56, 23, { color: black, align: "center" });
  footer(s, 4, "Task 18 到 23");
  note(s, "来源：docs/architecture.md；rtl/pipeline_cpu.v；docs/progress.md。");
}

// 5 Verification table
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "验证覆盖", "从模块到发布清单均输出明确 PASS 或 FAIL");
  const values = [
    ["层次", "覆盖内容", "结果"],
    ["ISA", "RV32UI Core 29 项 + Memory 10 项", "PASS"],
    ["Reference", "14 个入口与首差检测", "14 / 0"],
    ["Pipeline", "10 个 Hazard 背压 Reset Trace 入口", "PASS"],
    ["GCC", "两项程序 × 固定/随机延迟", "Trace 一致"],
    ["Application", "Capture MMIO SoC UART/SPI Python/VCD", "PASS"],
    ["Release", "范围审计 + 唯一最终 bitstream SHA-256", "PASS"],
  ];
  const t = s.tables.add({ rows: values.length, columns: 3, left: 92, top: 174, width: 1090, height: 390, values });
  applyTableStyle(t, values.length, 3, [190, 690, 210]);
  text(s, "比较器在第一条不一致提交处报告字段、PC 和 instruction", 94, 590, 1080, 44, 20, { bold: true, color: orange, align: "center" });
  footer(s, 5, "2026-09-16 自动回归");
  note(s, "来源：tmp/final_regression_summary.txt；docs/progress.md。");
}

// 6 Hazards
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "Hazard 控制", "前递、暂停和冲刷分别处理三类依赖");
  const items = [
    ["Forwarding", "EX/MEM 优先于 MEM/WB\n排除 Load、x0、错误写回", cyan],
    ["Load-Use Stall", "冻结 PC 与 IF/ID\n向 ID/EX 注入 Bubble", orange],
    ["Branch Jump Flush", "EX 级重定向\n冲刷错误路径副作用", blue],
  ];
  items.forEach((it, i) => {
    const x = 80 + i * 390;
    box(s, x, 185, 350, 300, white, it[2], 12);
    box(s, x, 185, 350, 62, it[2], "none", 12);
    text(s, it[0], x + 12, 185, 326, 62, 24, { bold: true, color: white, align: "center" });
    text(s, it[1], x + 26, 278, 298, 130, 22, { align: "center" });
  });
  text(s, "WB during hold", 180, 526, 220, 38, 18, { bold: true, color: navy, align: "center" });
  text(s, "定向用例证明数据事务等待期间 WB 值仍可前递", 410, 520, 690, 50, 20, { color: black });
  footer(s, 6, "Task 23 10 entries PASS");
  note(s, "来源：scripts/run_task23_regression.ps1；tb/data/task23_wb_hold.mem。");
}

// 7 CoreMark metrics
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "CoreMark 与分支预测", "同一 RV32I 镜像的 Predictor Off 和 On 均通过官方 CRC");
  const values = [
    ["指标", "当前值", "证据口径"],
    ["Predictor Off", "2,106,042 cycles", "CPI 2.7143"],
    ["Predictor On", "1,852,156 cycles", "CPI 2.3747"],
    ["周期减少", "253,886", "12.06%"],
    ["BTB", "203,492 hit", "51,908 misprediction"],
    ["性能事件", "10 项 64-bit", "含 predict、hit、mispredict"],
  ];
  const t = s.tables.add({ rows: values.length, columns: 3, left: 90, top: 172, width: 1100, height: 360, values });
  applyTableStyle(t, values.length, 3, [330, 330, 440]);
  box(s, 90, 563, 1100, 60, "#FFF3E8", orange, 8);
  text(s, "以上为 RTL 仿真 Before/After；实体板成绩只接受真实串口日志", 108, 568, 1065, 50, 19, { bold: true, color: "#8A3B12", align: "center" });
  footer(s, 7, "CoreMark commit 1f483d5b");
  note(s, "来源：release/evidence/automated_metrics.json；third_party/coremark 固定提交。CoreMark/MHz 属于 RTL 仿真估算。");
}

// 8 PDS chart
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "最终配置资源与时序", "唯一最终配置在 50 MHz 下满足全部时序约束");
  const chart = s.charts.add("bar", {
    position: { left: 72, top: 165, width: 730, height: 410 },
    categories: ["FF", "LUT"],
    series: [{ name: "最终配置资源", values: [3129, 3459], fill: blue }],
    barOptions: { direction: "bar", grouping: "clustered", gapWidth: 55 },
    hasLegend: false,
    xAxis: { min: 0, max: 5000, majorUnit: 1000, textStyle: { typeface: font, fontSize: 15 }, majorGridlines: { fill: "#D9D9D9", width: 1 } },
    yAxis: { textStyle: { typeface: font, fontSize: 16 } },
    dataLabels: { showValue: true, position: "outEnd", textStyle: { typeface: font, fontSize: 15 } },
    chartFill: white,
    plotAreaFill: white,
  });
  applyPresentationChartFont(chart, { fontFamily: font });
  box(s, 850, 178, 330, 98, pale, blue, 8); text(s, "最终时序", 872, 186, 286, 26, 18, { bold: true, color: navy, align: "center" }); text(s, "Fmax 57.6735 MHz\nWNS +2.661 / +0.312 ns", 872, 214, 286, 52, 16, { align: "center" });
  box(s, 850, 306, 330, 98, "#EAF7F5", cyan, 8); text(s, "片上存储", 872, 314, 286, 26, 18, { bold: true, color: cyan, align: "center" }); text(s, "5.5 个 DRM18K 等效块", 872, 350, 286, 40, 16, { align: "center" });
  text(s, "bitstream SHA-256\n2C09E690...964746E", 836, 460, 360, 70, 18, { color: gray, align: "center" });
  footer(s, 8, "PDS 2024.2-SP2");
  note(s, "来源：release/evidence/automated_metrics.json；fpga/task30_logic_analyzer PDS 报告。资源为综合结果。");
}

// 9 Branch predictor
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "16 项分支预测器", "直接映射 BTB 与 2-bit 饱和计数器在 EX 级校验");
  box(s, 80, 175, 480, 390, pale, blue, 12);
  text(s, "BTB", 110, 194, 420, 44, 27, { bold: true, color: navy, align: "center" });
  text(s, "16 entries\nPC 直接索引\n32-bit target", 110, 256, 420, 142, 34, { bold: true, color: blue, align: "center" });
  text(s, "条件分支使用 2-bit 计数器\n错误方向或目标在 EX 恢复", 115, 432, 410, 90, 19, { align: "center" });
  const sigs = [["索引", "PC[5:2]"], ["标签", "PC[31:6]"], ["更新", "EX 级真实方向与目标"], ["事件", "predict / BTB hit / mispredict"]];
  sigs.forEach((r, i) => { const y = 190 + i * 95; box(s, 645, y, 500, 72, white, i % 2 ? cyan : blue, 8); text(s, r[0], 665, y, 110, 72, 20, { bold: true, color: i % 2 ? cyan : blue, align: "center" }); text(s, r[1], 790, y, 335, 72, 18); });
  text(s, "Predictor Off 和 On 使用相同程序镜像并通过官方 CRC", 645, 587, 500, 38, 19, { bold: true, color: orange, align: "center" });
  footer(s, 9, "Task 32 Before / After PASS");
  note(s, "来源：rtl/branch_predictor.v；docs/performance_baseline.md；release/evidence/automated_metrics.json。");
}

// 10 Logic analyzer
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "八通道逻辑分析仪", "配置、采集、软件解析与 VCD 构成端到端闭环");
  const nodes = [
    ["J8 激励", "static  counter\nUART  SPI", 70, orange],
    ["J8 输入", "8 通道\n3.3 V", 290, blue],
    ["Capture Engine", "trigger\npre + post", 510, cyan],
    ["RISC-V 软件", "MMIO\nUART/SPI 解析", 730, navy],
    ["Python", "协议复核\nVCD / JSON", 950, blue],
  ];
  nodes.forEach(([a,b,x,c]) => { box(s, x, 220, 180, 220, white, c, 12); box(s, x, 220, 180, 56, c, "none", 12); text(s, a, x + 6, 220, 168, 56, 22, { bold: true, color: white, align: "center" }); text(s, b, x + 18, 292, 144, 112, 21, { align: "center" }); });
  for (const x of [250, 470, 690, 910]) box(s, x, 326, 40, 4, gray, "none");
  text(s, "8 通道  |  256 samples  |  最高 50 MS/s  |  触发延迟 0 个额外 sample tick", 90, 500, 1060, 48, 22, { bold: true, color: navy, align: "center" });
  text(s, "13 字节带 XOR 校验配置包，无需重新综合即可改变模式、数据、速率与触发", 90, 566, 1060, 42, 19, { color: gray, align: "center" });
  footer(s, 10, "Task 30 自动化 PASS");
  note(s, "来源：docs/application_logic_analyzer.md；software/task30_logic_analyzer；python/logic_analyzer.py。");
}

// 11 Demo evidence
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "现场演示与证据", "唯一最终 bitstream 完成应用演示");
  const values = [
    ["动作", "脚本或工具", "PASS 条件"],
    ["下载", "PDS Programmer", "SHA-256 与最终包一致"],
    ["串口", "CP2102 115200 8N1", "LA_READY 与配置响应正确"],
    ["物理回环", "run_task30_board.ps1", "4 模式 × 20 次，VCD/JSON 一致"],
    ["断电压力", "run01 / run02 / run03", "同一 SHA-256，三轮结果一致"],
  ];
  const t = s.tables.add({ rows: values.length, columns: 3, left: 80, top: 172, width: 1120, height: 350, values });
  applyTableStyle(t, values.length, 3, [240, 350, 530]);
  box(s, 80, 555, 1120, 70, "#EAF7F5", cyan, 8);
  text(s, "MES50HP 下载 DONE=1，J8 四模式各 20 次，共 80/80 实体回环 PASS", 104, 562, 1070, 54, 21, { bold: true, color: cyan, align: "center" });
  footer(s, 11, "复现说明 docs/reproduction.md");
  note(s, "来源：docs/reproduction.md；release/materials/field_recovery_card.md。");
}

// 12 Status
{
  const s = deck.slides.add(); s.background.fill = white; title(s, "当前结论", "自动化、PDS 与 J8 实体闭环已通过");
  box(s, 82, 180, 520, 330, "#EAF7F5", cyan, 14);
  text(s, "已完成", 110, 204, 464, 52, 30, { bold: true, color: cyan, align: "center" });
  text(s, "RV32I 与 Reference\n五级流水线与 Hazard\nCoreMark 与 BTB 对比\n唯一最终 PDS bitstream\nJ8 实体回环 80/80", 130, 278, 420, 190, 23, { align: "center" });
  box(s, 678, 180, 520, 330, "#FFF3E8", orange, 14);
  text(s, "待补证", 706, 204, 464, 52, 30, { bold: true, color: orange, align: "center" });
  text(s, "实体 CoreMark 计分\nFabric Debugger 波形\n三轮断电压力\n最终视频素材", 726, 288, 420, 170, 23, { align: "center" });
  text(s, "当前版本：competition_final_candidate", 100, 564, 1080, 52, 27, { bold: true, color: navy, align: "center" });
  footer(s, 12, "BTB 已完成，RLE 保持冻结");
  note(s, "来源：docs/progress.md；release/HANDOFF.md；release/evidence/logic_analyzer_board_final。其余实体证据继续按真实结果更新。");
}

const staging = path.join(ROOT, ".codex-finalizer");
await fs.mkdir(staging, { recursive: true });
const candidatePath = path.join(staging, "defense_presentation_candidate.pptx");
await (await PresentationFile.exportPptx(deck)).save(candidatePath);

const result = await finalizePresentation({
  explicitTotalSlideCount: 12,
  requiredNativeTableOwnerSlides: [5, 7, 11],
  requiredNativeChartOwnerSlides: [8],
  materializeLiteralChartWorkbooks: true,
  workspaceDir: ROOT,
  candidatePath,
  finalPath: FINAL_PPTX,
  pythonExecutable: RUNTIME_PYTHON,
  integrityValidatorPath: path.join(SKILL_DIR, "container_tools", "inspect_presentation_package_integrity.py"),
  layoutValidatorPath: path.join(SKILL_DIR, "container_tools", "inspect_presentation_layout_geometry.py"),
  layoutArgs: [
    "--expected-slide-size-emu", "12192000,6858000",
    "--validate-bullet-geometry",
    "--validate-heading-fit",
    "--require-native-table-slide", "5",
    "--require-native-table-slide", "7",
    "--require-native-table-slide", "11",
  ],
  requiredNativeTableOwnerSlides: [5, 7, 11],
  requiredNativeChartOwnerSlides: [8],
  fontPolicy: { basis: "design", families: [font] },
  verifyArtifactToolImport: true,
  receiptPath: path.join(staging, "defense_presentation.validation.json"),
});

console.log(`WROTE ${FINAL_PPTX}`);
console.log(JSON.stringify(result));
