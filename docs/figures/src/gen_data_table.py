# -*- coding: utf-8 -*-
"""生成设计文档的数据图（图 3-9 全表 / 图 3-10 关键指标卡）为 .drawio 文件。

样式直接复用 gen_data_figures.py 的 Fig 类与 PAL 配色（微软雅黑、rounded=0、
strokeWidth=1.5、底部灰字数据源），与正文图 3-5～图 3-8 完全同源。

  fig3_9  关键数据汇总表   5 分区 28 行，纵向长表，适合作为正文附录表
  fig3_10 关键指标卡       4×3 卡 + 止损条，宽而短，适合正文插图与幻灯片

数据来源（逐个数字可查）：release/evidence/claims_map.md
    §1   交付位流 C017ED10…：LUT / FF / DRM / APM / WNS / 估算 Fmax
    §2   分支预测 Before/After（RTL 仿真口径）
    §3.1/§3.1b/§3.1c/§3.3  CoreMark 实板分数（rv32i 与 rv32im 分列）
    §4   五模式板级验收 100/100
    §5   止损记录（I/D Cache、行式突发、DDR3）
  release/evidence/automated_metrics.json（资源与时序的机器可读副本）

用法：python gen_data_table.py
"""
from __future__ import annotations

import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from gen_data_figures import PAL, Fig  # noqa: E402  同一套样式，不重复实现

MARGIN = 60
W_TOTAL = 1320

TITLE = "关键数据汇总：处理器 / CoreMark / 分支预测 / 逻辑分析仪 / 默认关闭的试验项"
SUBTITLE = "盘古 50（PGL50H-6IFBG484）· 85 MHz 交付位流"

# ---------------------------------------------------------------- 图 3-9 全表
COL_PROJ = (MARGIN, 360)
COL_VAL = (MARGIN + 360, 340)
COL_NOTE = (MARGIN + 700, 620)
ROW_H, SEC_H, HEAD_H = 46, 44, 54

SECTIONS = [
    ("A　处理器与交付位流（85 MHz，All Constraints Met）", "blue", [
        ("指令集", "RV32I + M 扩展", "rv32i 是默认的对比基准；M 扩展是额外做的增强，不属于官方必做项"),
        ("流水线", "5 级 IF/ID/EX/MEM/WB", "前递、Load-Use 暂停、分支冲刷"),
        ("LUT", "4995", "布局布线后统计，交付位流"),
        ("触发器 FF", "3907", "同上"),
        ("DRAM18K", "6.0", "同上"),
        ("乘法器 APM", "4", "供 M 扩展乘除法使用"),
        ("Setup WNS", "+0.577 ns", "85 MHz 约束下 All Constraints Met"),
        ("估算 Fmax", "89.3841 MHz", "PDS 时序分析估算值，不是板上实测"),
        ("板上最高工作频率", "85 MHz", "逻辑分析仪应用上界；90 MHz 的 SPI 模式可复现挂死"),
    ]),
    ("B　CoreMark 实板分数（以 rv32im 为主；计分位流与交付位流不是同一颗）", "orange", [
        ("CoreMark/MHz（rv32im）", "2.272", "硬件乘除法（额外做的 M 扩展）；为 rv32i 软件模拟的 0.936 的 2.43 倍"),
        ("Score（rv32im @ 85 MHz）", "193.192", "计分位流 EE8B6536…，4000 迭代 20.704 s"),
        ("M 扩展指令", "8 条", "mul / mulh / mulhsu / mulhu / div / divu / rem / remu，流水线与单周期均实现"),
        ("官方 CRC 校验", "全部通过", "输出里有 Correct operation validated."),
        ("CoreMark/MHz（rv32i，只作对照）", "0.936", "乘除法由软件模拟；只用来算 2.43 倍，不作最终成绩"),
        ("Score（rv32i @ 85 MHz，只作对照）", "79.587", "计分位流 751C692B…，与上面 2.272 同频同源对照"),
    ]),
    ("C　分支预测前后对比（RTL 仿真，不和实板数据混在一起说）", "green", [
        ("执行周期 cycles", "1,604,264 → 1,251,724", "Predictor Off → On，减少 21.98%"),
        ("CPI", "2.0670 → 1.5907", "周期 / 退休指令"),
        ("分支冲刷 flush", "161,742 → 69,120", "同时刻 BTB 命中 221,615 次"),
        ("预测器结构", "16 项 BTB + 2-bit 饱和计数器", "只索引 PC 低位"),
    ]),
    ("D　八通道多协议逻辑分析仪（交付位流）", "purple", [
        ("通道数", "8", "J8 外部 8 路 / Core 内部观测点，可切换"),
        ("采集深度", "2048 点", "片上 Raw 缓存"),
        ("触发", "电平 / 边沿", "前触发与后触发样本数由上位机配置"),
        ("采集模式", "static / counter / uart / spi / mirror", "13 字节 0xA5 报文，切模式不重新综合"),
        ("采样率", "85 MHz（sample_div=0）", "与系统时钟同频"),
        ("板级验收", "100 / 100 全部通过", "五模式各 20 次，85 MHz 交付位流"),
    ]),
    ("E　默认关闭与未接入（做了也量过，更慢或没接通所以关掉）", "red", [
        ("2 路组相联 I-Cache", "1,251,724 → 2,891,324", "拍；慢了 2.31 倍，默认关闭"),
        ("2 路组相联 D-Cache", "1,251,724 → 1,348,302", "拍；慢了 7.7%，默认关闭"),
        ("行式突发 burst", "48 → 30", "总线周期数，减少 37.5%（保留）"),
        ("外部 DDR3", "板级连通通过", "还没接进 CPU 的存储路径"),
    ]),
]


def build_table() -> Fig:
    rows_h = sum(SEC_H + ROW_H * len(rows) for _, _, rows in SECTIONS)
    header_y = 118
    table_bottom = header_y + HEAD_H + rows_h
    page_h = table_bottom + 24

    fig = Fig("图3-9 关键数据汇总表", 1440, page_h)
    fig.text(MARGIN, 30, W_TOTAL, 44, TITLE, size=17, bold=True)
    fig.text(MARGIN, 76, W_TOTAL, 30, SUBTITLE, size=13, color="#5F5F5F")

    for (cx, cw), label in zip((COL_PROJ, COL_VAL, COL_NOTE), ("项目", "数值", "说明")):
        fig.rect(cx, header_y, cw, HEAD_H, PAL["gray"][0], PAL["gray"][1])
        fig.text(cx, header_y, cw, HEAD_H, label, size=15, bold=True, align="center")

    y = header_y + HEAD_H
    stripe = 0
    for title, pal, rows in SECTIONS:
        fill, stroke = PAL[pal]
        fig.rect(MARGIN, y, W_TOTAL, SEC_H, fill, stroke)
        fig.text(MARGIN + 12, y, W_TOTAL - 32, SEC_H, f"{title}　（{len(rows)} 项）",
                 size=14, bold=True, align="left")
        y += SEC_H
        for proj, val, note in rows:
            bg = "#FFFFFF" if stripe % 2 == 0 else "#F7F7F7"
            for cx, cw in (COL_PROJ, COL_VAL, COL_NOTE):
                fig.rect(cx, y, cw, ROW_H, bg, "#D6D6D6")
            fig.text(COL_PROJ[0] + 10, y, COL_PROJ[1] - 16, ROW_H, proj, size=13, align="left")
            fig.text(COL_VAL[0], y, COL_VAL[1], ROW_H, val, size=13, bold=True, align="center")
            fig.text(COL_NOTE[0] + 10, y, COL_NOTE[1] - 16, ROW_H, note, size=12, align="left")
            stripe += 1
            y += ROW_H

    print(f"  fig3-9 table: page=1440x{page_h}  rows={sum(len(r) for _, _, r in SECTIONS)}")
    return fig


# ---------------------------------------------------------------- 图 3-10 关键指标卡
CARDS = [
    # (类别, 大数字, 说明, 配色)
    ("CoreMark/MHz（rv32im）", "2.272", "硬件乘除法；相对 rv32i 软件模拟的 0.936 为 2.43 倍", "orange"),
    ("CoreMark Score @ 85 MHz（rv32im）", "193.192", "计分位流 EE8B6536…，4000 迭代 20.704 s", "orange"),
    ("M 扩展（RV32IM）", "8 条指令", "额外做的，不属于官方必做项：mul/mulh/mulhsu/mulhu/div/divu/rem/remu，流水线与单周期都实现", "orange"),
    ("官方 CRC 校验", "全部通过", "输出里有 Correct operation validated.", "orange"),
    ("资源 LUT / FF", "4995 / 3907", "交付位流 C017ED10…，All Constraints Met", "blue"),
    ("DRAM18K / 乘法器 APM", "6.0 / 4", "片上 BRAM 与 M 扩展乘法器", "blue"),
    ("Setup WNS", "+0.577 ns", "85 MHz 约束下时序全部通过", "blue"),
    ("估算 Fmax", "89.3841 MHz", "PDS 时序估算，不是板上实测", "blue"),
    ("板上最高工作频率", "85 MHz", "逻辑分析仪应用上界（90 MHz 的 SPI 挂死）", "green"),
    ("实板 CPI", "≈1.50", "窗口敏感，只写两位小数", "green"),
    ("分支预测 Before → After", "2.0670 → 1.5907", "CPI；flush 161,742 → 69,120（RTL 仿真）", "green"),
    ("逻辑分析仪板级验收", "100 / 100", "五模式 ×20；8 通道，2048 点，85 MHz 采样", "purple"),
]

STOP_LOSS = (
    "默认关闭的试验项：2 路组相联 I-Cache 从 1,251,724 拍变成 2,891,324 拍（慢了 2.31 倍）　｜　"
    "2 路组相联 D-Cache 变成 1,348,302 拍（慢了 7.7%）　｜　"
    "行式突发 48 → 30 总线周期（减少 37.5%，保留）　｜　外部 DDR3 板级连通通过，还没接进 CPU"
)


def build_cards() -> Fig:
    card_w, card_h, gap = 320, 190, 24
    cols = 4
    grid_x = MARGIN
    grid_y = 122
    rows = (len(CARDS) + cols - 1) // cols
    grid_h = rows * card_h + (rows - 1) * gap
    strip_y = grid_y + grid_h + 26
    strip_h = 86
    page_h = strip_y + strip_h + 24

    fig = Fig("图3-10 关键指标卡", 1440, page_h)
    fig.text(MARGIN, 30, W_TOTAL, 44,
             "关键指标：交付位流 85 MHz · CoreMark 计分位流 · 逻辑分析仪", size=17, bold=True)
    fig.text(MARGIN, 76, W_TOTAL, 30, SUBTITLE, size=13, color="#5F5F5F")

    for idx, (label, big, note, pal) in enumerate(CARDS):
        cx = grid_x + (idx % cols) * (card_w + gap)
        cy = grid_y + (idx // cols) * (card_h + gap)
        fill, stroke = PAL[pal]
        fig.rect(cx, cy, card_w, card_h, fill, stroke)
        fig.line(cx + 14, cy + 40, cx + card_w - 14, cy + 40, stroke, 1, dashed=True)
        fig.text(cx + 10, cy + 6, card_w - 20, 30, label, size=12, align="left")
        fig.text(cx + 10, cy + 44, card_w - 20, 66, big, size=27, bold=True, align="center")
        fig.text(cx + 12, cy + 114, card_w - 24, 66, note, size=11, align="left")

    fig.rect(MARGIN, strip_y, W_TOTAL, strip_h, PAL["red"][0], PAL["red"][1])
    fig.text(MARGIN + 14, strip_y + 6, W_TOTAL - 28, strip_h - 12, STOP_LOSS, size=12.5,
             color=PAL["red"][1], bold=True, align="left")

    print(f"  fig3-10 cards: page=1440x{page_h}  cards={len(CARDS)}  grid={cols}x{rows}")
    return fig


# ---------------------------------------------------------------- 图 3-11 完成情况清单
BASE_TASKS = [
    ("完整 RV32I 指令集",
     "全部基础指令覆盖；上游 RV32UI Core 29 项 + Memory 10 项全部通过"),
    ("五级流水线 IF/ID/EX/MEM/WB",
     "数据前递、Load-Use 暂停、分支与跳转冲刷，按周期逐条回归"),
    ("UART · GPIO · 定时器",
     "统一 MMIO 接入；CPU 里没有任何设备专用端口或设备状态机"),
    ("CoreMark 上板实测",
     "官方 CRC 全部通过，运行时间满足赛题不少于 10 秒的要求"),
    ("板级时序与资源",
     "4995 LUT / 3907 FF / 6.0 DRM18K；WNS +0.577 ns，板上跑 85 MHz"),
]

ADV_TASKS = [
    ("done", "16 项 BTB + 2-bit 饱和预测器",
     "打开预测后：CPI 2.0670 → 1.5907，分支冲刷 161,742 → 69,120（RTL 仿真）"),
    ("done", "机器模式异常与中断 + 定时器中断",
     "自检条目 M-01～M-24 全部通过；板级中断周期 250.348 ms，计数逐次递增"),
    ("done", "行式突发总线（burst）",
     "总线周期 48 → 30，减少 37.5%"),
    ("stop", "2 路组相联 I-Cache / D-Cache",
     "做了也量过：I-Cache 从 1,251,724 拍变成 2,891,324 拍（慢了 2.31 倍），"
     "D-Cache 变成 1,348,302 拍（慢了 7.7%），所以默认关闭"),
    ("stop", "外部 DDR3 存储后端",
     "板级连通性通过；还没接进 CPU 的存储路径"),
]

EXTRA_NOTE = (
    "额外做的（不属于官方必做项，也不属于高阶项）—— 完整 M 扩展 RV32IM：\n"
    "mul / mulh / mulhsu / mulhu / div / divu / rem / remu 共 8 条乘除法指令，流水线与单周期两个 CPU 都做了；"
    "CoreMark 拿到 193.192 分、每兆赫 2.272 分，是不加 M 扩展时的 2.43 倍。"
)

APP_NOTE = (
    "自研应用 —— 八通道多协议逻辑分析仪：\n"
    "static / counter / uart / spi / mirror 五种采集模式各 20 次，板级验收 100/100 全部通过；"
    "8 通道、2048 点缓存，85 MHz 采样与系统时钟同频。"
)



def _panel_h(n_rows: int, row_h: int, footer_h: int) -> int:
    return 54 + row_h * n_rows + 16 + footer_h


def _panel(fig: Fig, x: int, y: int, w: int, title: str, count: str, pal: str,
           rows: list[tuple], row_h: int = 96, with_pill: bool = False,
           footer: str = "", footer_h: int = 0) -> int:
    """画一个任务面板，返回面板底部的 y。"""
    fill, stroke = PAL[pal]
    head_h = 54
    body_h = row_h * len(rows) + 16 + footer_h
    fig.rect(x, y, w, head_h + body_h, "#FFFFFF", stroke)
    fig.rect(x, y, w, head_h, fill, stroke)
    fig.text(x + 14, y, w - 200, head_h, title, size=15, bold=True, align="left")
    fig.text(x + w - 190, y, 176, head_h, count, size=12, align="center")

    ry = y + head_h
    for row in rows:
        if with_pill:
            status, name, detail = row
            tag, tag_pal = ("已完成", "green") if status == "done" else ("默认关闭", "orange")
            tf, ts = PAL[tag_pal]
            fig.rect(x + 14, ry + 12, 78, 26, tf, ts)
            fig.text(x + 14, ry + 12, 78, 26, tag, size=10.5, bold=True, align="center")
            tx = x + 104
        else:
            name, detail = row
            fig.rect(x + 14, ry + 12, 22, 26, fill, stroke)
            fig.text(x + 14, ry + 12, 22, 26, "✓", size=12, bold=True, align="center")
            tx = x + 48
        fig.text(tx, ry + 8, x + w - tx - 16, 32, name, size=13, bold=True, align="left")
        fig.text(tx, ry + 42, x + w - tx - 16, 48, detail, size=11, align="left")
        fig.line(x + 14, ry + row_h, x + w - 14, ry + row_h, "#E2E2E2", 1)
        ry += row_h

    if footer_h:
        fig.rect(x, ry, w, footer_h, "#F7F7F7", stroke)
        fig.text(x + 16, ry + 10, w - 32, footer_h - 20, footer, size=10.5,
                 color="#5F5F5F", align="left")
    return y + head_h + body_h


def build_status() -> Fig:
    panel_w, gap = 640, 40
    left_x = MARGIN
    right_x = MARGIN + panel_w + gap
    top_y, row_h = 122, 96
    left_bottom = top_y + _panel_h(len(BASE_TASKS), row_h, 0)
    right_bottom = top_y + _panel_h(len(ADV_TASKS), row_h, 0)
    panel_bottom = max(left_bottom, right_bottom)
    extra_y = panel_bottom + 24
    extra_h = 96
    app_y = extra_y + extra_h + 18
    app_h = 82
    page_h = app_y + app_h + 24

    fig = Fig("图3-11 基础任务、进阶任务与额外做的", 1440, page_h)
    fig.text(MARGIN, 30, W_TOTAL, 44,
             "任务完成情况：基础任务 · 进阶任务 · 额外做的", size=17, bold=True)
    fig.text(MARGIN, 76, W_TOTAL, 30,
             "盘古 50（PGL50H-6IFBG484）· 85 MHz 交付位流",
             size=13, color="#5F5F5F")

    _panel(fig, left_x, top_y, panel_w, "基础任务（官方必做）",
           f"全部完成　{len(BASE_TASKS)}/{len(BASE_TASKS)}", "green", BASE_TASKS, row_h)
    _panel(fig, right_x, top_y, panel_w, "进阶任务（官方高阶项）",
           "3 项完成 · 2 项试过默认关闭", "blue", ADV_TASKS, row_h, with_pill=True)

    # 额外做的：M 扩展单独占一条，既不算基础也不算高阶
    fig.rect(MARGIN, extra_y, W_TOTAL, extra_h, PAL["orange"][0], PAL["orange"][1])
    fig.text(MARGIN + 16, extra_y + 8, W_TOTAL - 32, extra_h - 16,
             EXTRA_NOTE, size=13, color=PAL["orange"][1], bold=True, align="left")

    fig.rect(MARGIN, app_y, W_TOTAL, app_h, PAL["purple"][0], PAL["purple"][1])
    fig.text(MARGIN + 16, app_y + 8, W_TOTAL - 32, app_h - 16,
             APP_NOTE, size=12.5, color=PAL["purple"][1], bold=True, align="left")

    print(f"  fig3-11 status: page=1440x{page_h}  base={len(BASE_TASKS)}  adv={len(ADV_TASKS)}")
    return fig


if __name__ == "__main__":
    out = pathlib.Path(__file__).resolve().parent
    build_table().save(out / "fig3_9_data_summary.drawio")
    build_cards().save(out / "fig3_10_key_metrics.drawio")
    build_status().save(out / "fig3_11_completion_status.drawio")
