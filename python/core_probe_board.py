"""板级验收：逻辑分析仪"双源可选"的 Core 内部观测点（core 模式）。

为什么单独一个入口：`run_logic_analyzer_serial.py --mode core` 只能采一组默认触发，
而这项功能的说服力在于"同一台仪器、同一个位流，换个触发就能回答不同的问题"，
所以这里采两组窗口：
  * flush_trigger：触发 = ch6 event_flush 上升沿 —— 窗口以一次控制流冲刷为中心，
    回答"这次冲刷是怎么来的"；
  * stall_trigger：触发 = ch5 event_stall 上升沿 —— 窗口以一次流水线暂停为中心，
    回答"这条指令为什么没往前走"。

判据在 logic_analyzer_serial.run_captures 的 mode == "core" 分支里：
窗口点数、ch7 提交脉冲数、ch0 取指请求拍数；这里只负责组织两组采集并汇总。
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from logic_analyzer_serial import default_config, run_captures

FLUSH_MASK = 0x40   # ch6 = event_flush
STALL_MASK = 0x20   # ch5 = event_stall


def capture_group(port: str, output: Path, mask: int, runs: int, baud: int,
                  timeout: float, clock_hz: int) -> list[dict]:
    knobs = {"trigger_mask": mask}
    default_config("core", 0, clock_hz, baud)   # 保持与 run_captures 内部同一处推导
    summaries = run_captures(port, output, "core", 0, runs, baud, timeout,
                             clock_hz=clock_hz, knobs=knobs)
    for run in summaries:
        print(f"CORE PROBE {output.name} run={run['run']} samples={run['samples']} "
              f"trigger={run['trigger']} commits={run['core_commits']} "
              f"stalls={run['core_stalls']} flushes={run['core_flushes']}")
    return summaries


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("port")
    parser.add_argument("--output", type=Path, default=Path("release/evidence/core_probe_board"))
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--clock-hz", type=int, default=85_000_000)
    args = parser.parse_args()

    args.output.mkdir(parents=True, exist_ok=True)
    flush = capture_group(args.port, args.output / "flush_trigger", FLUSH_MASK,
                          args.runs, args.baud, args.timeout, args.clock_hz)
    stall = capture_group(args.port, args.output / "stall_trigger", STALL_MASK,
                          args.runs, args.baud, args.timeout, args.clock_hz)

    # 汇总口径写进一个 json，材料里引用数字时不必再去翻两棵目录。
    total_commits = sum(run["core_commits"] for run in flush + stall)
    all_runs = flush + stall
    summary = {
        "captures": len(all_runs),
        "runs_per_trigger": args.runs,
        "flush_trigger_samples": [run["samples"] for run in flush],
        "stall_trigger_samples": [run["samples"] for run in stall],
        "total_commit_pulses": total_commits,
        "min_commits_per_window": min(run["core_commits"] for run in all_runs),
        "total_stall_pulses": sum(run["core_stalls"] for run in all_runs),
        "total_flush_pulses": sum(run["core_flushes"] for run in all_runs),
    }
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
    print(f"CORE PROBE SUMMARY captures={summary['captures']} "
          f"min_commits_per_window={summary['min_commits_per_window']} "
          f"stall_pulses={summary['total_stall_pulses']} flush_pulses={summary['total_flush_pulses']}")
    print(f"CORE PROBE BOARD ACCEPTANCE PASS output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
