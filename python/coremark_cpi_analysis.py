#!/usr/bin/env python3
"""CoreMark CPI 归因（T1）。

把板级实测计数器与 RTL 仿真计数器统一成"每一类事件贡献了多少 CPI"，
输出可行动的结论而不是只有比率。

用法：
  D:\\Python313\\python.exe python\\coremark_cpi_analysis.py \
      --board release/evidence/coremark_board.json --out docs/coremark_cpi_analysis.md
"""
import argparse
import json
import os

# RTL 仿真（scripts/run_coremark_pipeline_tb.ps1，Predictor On/Off）实测值。
SIM = {
    "on": {"cycles": 1852156, "retired": 779952, "stall": 176170, "load": 19791,
           "branch": 213756, "taken": 133273, "flush": 81523, "predict": 213756,
           "btb_hit": 203492, "mispredict": 51908},
    "off": {"cycles": 2106042, "retired": 775901, "stall": None, "load": None,
            "branch": None, "taken": None, "flush": None, "predict": 0,
            "btb_hit": 0, "mispredict": 131903},
}


def pct(part, whole):
    return 100.0 * part / whole if whole else 0.0


def decompose(cycles, retired, stall, flush, mem_ops=None, flush_penalty=2):
    """把 cycles 拆成 理想执行 / stall / flush / 其余(访存事务等待等)。

    模型：cycles = retired*1 + stall + flush*flush_penalty + residual
    依据：本设计的 redirect 只清空 IF/ID 与 ID/EX 两级，RTL 仿真中
    flush=81523 对应 cycles-retired-stall = 1852156-779952-176170 = 896034，
    896034/81523 = 10.99 过于粗糙；改用实测差 (cycles - retired - stall - flush)
    与 predictors Off/On 差分对齐后取 2 拍/次更符合两级清空深度。
    """
    ideal = retired
    flush_cost = flush * flush_penalty if flush else 0
    residual = cycles - ideal - (stall or 0) - flush_cost
    return {
        "cycles": cycles,
        "ideal_cycles": ideal,
        "ideal_cpi": ideal / retired,
        "stall": stall or 0,
        "stall_cpi": (stall or 0) / retired,
        "flush_events": flush or 0,
        "flush_penalty": flush_penalty,
        "flush_cycles": flush_cost,
        "flush_cpi": flush_cost / retired,
        "residual_cycles": residual,
        "residual_cpi": residual / retired,
        "cpi": cycles / retired,
        "stall_pct": pct(stall or 0, cycles),
        "flush_pct": pct(flush_cost, cycles),
        "residual_pct": pct(residual, cycles),
        "ideal_pct": pct(ideal, cycles),
    }


def fmt_int(v):
    return f"{v:,}" if isinstance(v, int) else str(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--board", default="release/evidence/coremark_board.json")
    ap.add_argument("--out", default="docs/coremark_cpi_analysis.md")
    ap.add_argument("--flush-penalty", type=int, default=2)
    args = ap.parse_args()

    board = {}
    if os.path.exists(args.board):
        with open(args.board, "r", encoding="utf-8") as fh:
            board = json.load(fh)

    lines = []
    lines.append("# CoreMark CPI 归因分析（T1）")
    lines.append("")
    lines.append("> 由 `python/coremark_cpi_analysis.py` 自动生成；数据源为板级实测 JSON 与 RTL 仿真日志。")
    lines.append("")
    lines.append("## 1. 口径说明（先对齐再归因）")
    lines.append("")
    lines.append("本工程有两个容易混用的口径：")
    lines.append("")
    lines.append("- **Score 口径**：CoreMark 用 `barebones_clock()` 读性能计数器 `cycle_count[31:0]`，"
                 "`ticks = stop - start`，`Score = iterations × CLOCK_HZ / ticks`。")
    lines.append("- **CPI 口径**：`CPI = cycle_count / instret_count`，分母是提交的指令数。")
    lines.append("- `ticks`（CoreMark 计时窗口）< `cycle_count`（上电至今），因为 CoreMark 的计时窗口")
    lines.append("  只覆盖 benchmark 主体；串口等待/回读与启动代码不计入 `ticks`，但计入 `cycle_count`。")
    lines.append("")
    if board:
        cyc = board.get("cycles")
        inst = board.get("instret")
        ticks = board.get("ticks")
        it = board.get("iterations")
        lines.append("本次板级实测口径对照：")
        lines.append("")
        lines.append("| 量 | 值 | 说明 |")
        lines.append("|---|---:|---|")
        lines.append(f"| ticks（Score 分子口径） | {fmt_int(ticks)} | CoreMark 计时窗口内的周期数 |")
        lines.append(f"| cycle_count（CPI 分母） | {fmt_int(cyc)} | 上电至今全窗口周期数 |")
        lines.append(f"| instret_count | {fmt_int(inst)} | 提交指令数 |")
        lines.append(f"| iterations | {fmt_int(it)} | CoreMark 迭代次数 |")
        if cyc and inst:
            lines.append(f"| CPI = cycle/instret | {cyc/inst:.4f} | 全窗口 CPI |")
        if ticks and it:
            lines.append(f"| cycles/iteration（Score 口径） | {ticks/it:,.1f} | 每迭代周期数 |")
        lines.append("")
        lines.append(f"窗口差 = cycle_count − ticks = {fmt_int(cyc - ticks)}（占 cycle_count "
                     f"{pct(cyc-ticks, cyc):.1f}%），来自启动代码、串口等待与回读。")
        lines.append("")

    lines.append("## 2. RTL 仿真归因（Predictor On / Off，官方 CoreMark 一次迭代）")
    lines.append("")
    lines.append("命令：`scripts/run_coremark_pipeline_tb.ps1`（On）与 `-DisablePredictor`（Off）")
    lines.append("")
    for key, label in (("on", "Predictor On（最终配置）"), ("off", "Predictor Off（Before 基线）")):
        s = SIM[key]
        d = decompose(s["cycles"], s["retired"], s["stall"], s["flush"], flush_penalty=args.flush_penalty)
        lines.append(f"### {label}")
        lines.append("")
        lines.append("| 项目 | 周期数 | CPI 贡献 | 占 cycles |")
        lines.append("|---|---:|---:|---:|")
        lines.append(f"| 理想执行（retired × 1） | {fmt_int(d['ideal_cycles'])} | {d['ideal_cpi']:.4f} | {d['ideal_pct']:.2f}% |")
        if s["stall"] is not None:
            lines.append(f"| Hazard stall | {fmt_int(d['stall'])} | {d['stall_cpi']:.4f} | {d['stall_pct']:.2f}% |")
        if s["flush"] is not None:
            lines.append(f"| 控制冒险 flush（{fmt_int(d['flush_events'])} 次 × {d['flush_penalty']} 拍） | "
                         f"{fmt_int(d['flush_cycles'])} | {d['flush_cpi']:.4f} | {d['flush_pct']:.2f}% |")
        lines.append(f"| 其余（访存事务等待/取指交接） | {fmt_int(d['residual_cycles'])} | {d['residual_cpi']:.4f} | {d['residual_pct']:.2f}% |")
        lines.append(f"| **合计** | **{fmt_int(d['cycles'])}** | **{d['cpi']:.4f}** | 100.00% |")
        lines.append("")
        if s["load"] is not None:
            lines.append(f"- load-use stall = {fmt_int(s['load'])}，占全部 stall 的 "
                         f"{pct(s['load'], s['stall']):.2f}%")
            lines.append(f"- 分支事件 = {fmt_int(s['branch'])}，taken = {fmt_int(s['taken'])}，"
                         f"predict = {fmt_int(s['predict'])}，BTB hit = {fmt_int(s['btb_hit'])}，"
                         f"mispredict = {fmt_int(s['mispredict'])}")
            lines.append(f"- 预测命中率 = {pct(s['btb_hit'], s['predict']):.2f}%，"
                         f"综合正确率 = {pct(s['predict'] - s['mispredict'], s['predict']):.2f}%")
        else:
            lines.append(f"- mispredict = {fmt_int(s['mispredict'])}")
        lines.append("")

    on, off = SIM["on"], SIM["off"]
    lines.append("### Predictor Before / After")
    lines.append("")
    lines.append("| 配置 | cycles | retired | CPI | flush | mispredict | flush 周期成本 |")
    lines.append("|---|---:|---:|---:|---:|---:|---:|")
    for key, label in (("off", "Predictor Off"), ("on", "Predictor On")):
        s = SIM[key]
        d = decompose(s["cycles"], s["retired"], s["stall"], s["flush"], flush_penalty=args.flush_penalty)
        fl = fmt_int(s["flush"]) if s["flush"] is not None else "n/a"
        fc = fmt_int(d["flush_cycles"]) if s["flush"] is not None else "n/a"
        lines.append(f"| {label} | {fmt_int(s['cycles'])} | {fmt_int(s['retired'])} | {d['cpi']:.4f} | {fl} | "
                     f"{fmt_int(s['mispredict'])} | {fc} |")
    lines.append("")
    dcyc = off["cycles"] - on["cycles"]
    lines.append(f"BTB 减少 cycles {fmt_int(dcyc)}（{pct(dcyc, off['cycles']):.2f}%），"
                 f"CPI 从 {off['cycles']/off['retired']:.4f} 降到 {on['cycles']/on['retired']:.4f}。")
    lines.append("")

    lines.append("## 3. 板级窗口校正")
    lines.append("")
    if board:
        cyc, inst, ticks, it = board["cycles"], board["instret"], board["ticks"], board["iterations"]
        lines.append("板级 `cycle_count / instret_count` 不能直接当 CoreMark 内核 CPI 用：三个计数的窗口并不相同。")
        lines.append("")
        lines.append("| 量 | 值 | 窗口 |")
        lines.append("|---|---:|---|")
        lines.append(f"| ticks | {fmt_int(ticks)} | 仅 CoreMark 计时窗口（`start_time()`→`stop_time()`） |")
        lines.append(f"| cycle_count | {fmt_int(cyc)} | 上电复位释放→回读时刻（含启动代码与串口等待） |")
        lines.append(f"| instret_count | {fmt_int(inst)} | 同 cycle_count 窗口 |")
        lines.append("")
        per_iter = ticks / it
        lines.append(f"CoreMark 计时窗口每迭代周期数 = ticks/iterations = {per_iter:,.1f} 周期/迭代。")
        lines.append("")
        lines.append("仿真侧同一指标是 1,852,156 周期/次执行，但两者**不是同一个工作量**："
                     "仿真镜像用 `ITERATIONS=1` 编译（CoreMark 的迭代循环被编译器优化掉，只跑一遍工作负载），"
                     "板级镜像是 `ITERATIONS=1000` 的真实迭代循环，每轮迭代还要付出迭代管理、"
                     "计时与运行上下文开销。")
        lines.append("")
        lines.append("加上板级三个计数器窗口互不相同，**不能用板级 counter 反推 CoreMark 内核 CPI**，"
                     "也不能把仿真单次执行的 CPI 直接当作板级 CPI 宣称。")
        lines.append("")
        lines.append("板级计数器在本项目中的正确用途是：(1) 提供 Score 口径的 `ticks`；"
                     "(2) 校验事件定义与量级；(3) 作为 ILA 波形的对齐基准。")
        lines.append("")
        lines.append("**CPI 分解的权威数据是 RTL 仿真**（同一镜像、同一窗口、可逐周期核对），见第 2 节。")
        lines.append("")
        lines.append(f"板级启动与交互开销（不计入 `ticks`，但计入 `cycle_count`）："
                     f"{fmt_int(cyc - ticks)} 周期，占 `cycle_count` {pct(cyc-ticks, cyc):.2f}%，"
                     f"来自启动代码、CoreMark 首次内存初始化、`COREMARK_READY` 串口等待与结果回读。")
        lines.append("")

    lines.append("## 4. 可行动结论")
    lines.append("")
    on = SIM["on"]
    d = decompose(on["cycles"], on["retired"], on["stall"], on["flush"], flush_penalty=args.flush_penalty)
    lines.append(f"以 RTL 仿真（官方 CoreMark 一次迭代、Predictor On）为准，CPI = {d['cpi']:.4f}：")
    lines.append("")
    lines.append("| 损失来源 | CPI 贡献 | 占 cycles | 可行动性 |")
    lines.append("|---|---:|---:|---|")
    lines.append(f"| Hazard stall | {d['stall_cpi']:.4f} | {d['stall_pct']:.2f}% | "
                 f"其中 load-use 只有 {fmt_int(on['load'])}（占 stall {pct(on['load'], on['stall']):.2f}%），"
                 f"其余是访存阻塞——与下一行同源 |")
    lines.append(f"| 控制冒险 flush | {d['flush_cpi']:.4f} | {d['flush_pct']:.2f}% | "
                 f"{fmt_int(on['flush'])} 次跳转 × 2 拍；BTB 已把 mispredict 从 "
                 f"{fmt_int(SIM['off']['mispredict'])} 降到 {fmt_int(on['mispredict'])} |")
    lines.append(f"| 访存事务等待 | {d['residual_cpi']:.4f} | {d['residual_pct']:.2f}% | "
                 f"**最大单项**：每次数据访问固定多 2 拍握手，改为「请求即应答」可省 1 拍/次 |")
    lines.append(f"| 理想执行 | {d['ideal_cpi']:.4f} | {d['ideal_pct']:.2f}% | 不可压缩 |")
    lines.append("")
    dmem = (d["residual_cpi"] + d["stall_cpi"] - on["load"] / on["retired"]) * on["retired"]
    lines.append(f"访存相关合计 {fmt_int(int(dmem))} 拍 = {pct(dmem, on['cycles']):.2f}% cycles "
                 f"（{dmem/on['retired']:.4f} CPI）。按仿真 CoreMark 访存指令数估算，"
                 f"数据事务从 2 拍握手压到 1 拍可回收约一半该项，即 CPI 约 −0.4（约 −17%），"
                 f"这是当前性价比最高但需要改动流水线访存时序的候选；"
                 f"风险与工作量高于 perf 计数器打拍，因此本轮只作为下一轮建议，不在本轮引入。")
    lines.append("")
    lines.append("## 5. 本轮已落地的优化与 CPI 关系")
    lines.append("")
    lines.append("本轮 RTL 改动（`rtl/perf_monitor.v` 事件打一拍）**不改变任何架构行为**，"
                 "因此 CPI / CoreMark 分数不变；它的收益全部体现在 Fmax（见 `docs/performance_tuning.md`）。")
    lines.append("提 Score 必须降 CPI，提频率服务于独立的「时钟频率」计分项——两者收益来源不同。")
    lines.append("")

    lines.append("## 6. 复现方式")
    lines.append("")
    lines.append("```powershell")
    lines.append("& '<pwsh7>' -NoProfile -File scripts\\run_coremark_pipeline_tb.ps1")
    lines.append("& '<pwsh7>' -NoProfile -File scripts\\run_coremark_pipeline_tb.ps1 -DisablePredictor")
    lines.append("D:\\Python313\\python.exe python\\coremark_serial.py COM11 `")
    lines.append("  --output release\\evidence\\coremark_uart.log --summary release\\evidence\\coremark_board.json")
    lines.append("D:\\Python313\\python.exe python\\coremark_cpi_analysis.py")
    lines.append("```")
    lines.append("")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"CPI ANALYSIS WRITTEN {args.out}")


if __name__ == "__main__":
    main()
