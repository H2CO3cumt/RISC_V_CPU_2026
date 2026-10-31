# -*- coding: utf-8 -*-
"""用 `ip_compiler -pre` 脚本枚举 PGL50H-FBG484 每个管脚的物理 Group（用于核对 DDR3 分组）。

为什么需要它：DDR3 PHY 有一条硬性物理要求——
**同一条 byte lane 的 DQ[7:0] / DQS / DM 必须落在同一个 I/O Group 里**。
布局阶段报的
    `Place-0054: IO instance ... must be constrained in same DQS group`
就是这个要求没满足。

本脚本借助 IP 自带的 UI API（`ui::getPkgPins` / `ui::getPkgPinGroup`）把包内全部管脚
与其所在 Group 打出来，然后与本工程手册管脚表交叉核对，
得出"手册给的分组是否落在同一 Group"（这是**只读核对**，不生成任何东西）。

用法：
  python scripts/ddr3_probe_pin_groups.py [--ipc <实例.ipc>]
输出：
  tmp/ddr3/pin_groups.json  —— { 管脚: {bank, group} }
  tmp/ddr3/lane_group_check.md —— 每个 byte lane 的分组核对结论
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')
PDS = Path(r'D:\Pango\PDS_2024.2-SP2')
IP_MODEL = PDS / 'ip/system_ip/ipsxb_hmic_s/ipsxb_hmic_eval/ipsxb_hmic_s'
OUT_JSON = REPO / 'tmp/ddr3/pin_groups.json'
OUT_MD = REPO / 'tmp/ddr3/lane_group_check.md'

PROBE_TCL = REPO / 'tmp/ddr3/probe_groups.tcl'


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--ipc', default=str(REPO / 'fpga/ddr3_smoke/ip/ddr3_mes50hp/ddr3_mes50hp.ipc'))
    ap.add_argument('--timeout', type=int, default=120)
    ap.add_argument('--reuse-log', action='store_true',
                    help='不重跑 ip_compiler，直接用已有 probe_groups.log 重跑解析（调解析器时用）')
    args = ap.parse_args()

    PROBE_TCL.parent.mkdir(parents=True, exist_ok=True)
    PROBE_TCL.write_text('\n'.join([
        '# 由 scripts/ddr3_probe_pin_groups.py 生成：把包内管脚与所属 Group 打出来。',
        '# API 用法照 ui.tcl：ui::getPkgPinGroup -name <管脚>、ui::getPkgPinBank -name <管脚>、',
        '# ui::isPkgPinDQS -name <管脚>、ui::getPkgPins -bank <B3> -group <G4>。',
        '# （第一版漏了 -name，所有调用都返回 "ERR:argument"。）',
        'set pins [ui::getPkgPins -bank B3]',
        'puts "PROBE_PINS_COUNT [llength $pins]"',
        'set groups {}',
        'foreach pin $pins {',
        '    if {[catch {set grp [ui::getPkgPinGroup -name $pin]} err]} { set grp "ERR" }',
        '    if {[lsearch -exact $groups $grp] < 0} { lappend groups $grp }',
        '    puts "PROBE_PIN $pin $grp"',
        '}',
        'puts "PROBE_GROUPS [lsort $groups]"',
        'foreach grp [lsort $groups] {',
        '    if {[catch {set gp [ui::getPkgPins -bank B3 -group $grp]} e]} { set gp "ERR" }',
        '    puts "PROBE_GROUP_PINS $grp [llength $gp] $gp"',
        '}',
        'puts "PROBE_DONE"',
        '',
    ]), encoding='utf-8')

    inst_dir = Path(args.ipc).parent
    log = inst_dir / 'probe_groups.log'
    cmd = [
        str(PDS / 'bin/ip_compiler.exe'), '-c', '-n', 'ddr3_mes50hp',
        '-i', str(Path(args.ipc)), '-m', str(IP_MODEL),
        '-pre', str(PROBE_TCL), '-tmp-dir', str(inst_dir / 'probe_tmp'),
        '-family', 'Logos', '-device', 'PGL50H', '-pack', 'FBG484', '-speed', '-6',
    ]
    if args.reuse_log and log.exists():
        print(f'复用已有探测日志 {log.name}（--reuse-log），只重跑解析')
    else:
        print('运行 ip_compiler 探测（完成后会强杀，属正常）...')
        # 每次先截断日志：否则上一次残留的行会和这一次混在一起，无法判断解析对不对。
        with log.open('w') as fh:
            try:
                p = subprocess.Popen(cmd, cwd=str(inst_dir), stdout=fh,
                                     stderr=subprocess.STDOUT)
                p.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                p.kill()

    text = log.read_text(encoding='utf-8', errors='replace')
    n = re.search(r'PROBE_PINS_COUNT\s+(\d+)', text)
    print('管脚数:', n.group(1) if n else '(未取到)')
    if 'PROBE_DONE' not in text:
        raise SystemExit(f'探测没有跑完，见 {log}（可能需要图形环境；本脚本是只读核对，失败不影响主流程）')

    # 注意 1：必须先把 `PROBE_GROUP_PINS <组名> <个数> <管脚表...>` 这些行从文本里"吃掉"，
    # 否则下面按 `PROBE_PIN` 找行的正则会连它们一起匹配，每组多出一条"以组名为管脚"的伪记录。
    # 注意 2：`is_dqs` 不能用"可选第三组 `(?:\s+(\S+))?`"来取——`\s` 会匹配换行，
    # 于是可选组跨过行尾把**下一行的 `PROBE_PIN`** 当成第三字段吞掉，两条日志才配成一条，
    # 结果 86 个管脚只解析出 43 条，且 is_dqs 全被写成 'PROBE_PIN'。
    # 探测日志本身只有 `PROBE_PIN <管脚> <组名>` 两个字段，这里就只取两个字段。
    scan = re.sub(r'^PROBE_GROUP_PINS .*$', '', text, flags=re.M)

    pins: dict[str, dict[str, str]] = {}
    for m in re.finditer(r'^PROBE_PIN[ \t]+(\S+)[ \t]+(\S+)[ \t]*$', scan, flags=re.M):
        pin, grp = m.group(1), m.group(2)
        pins[pin] = {'group': grp, 'is_dqs': '?'}
    count = re.search(r'PROBE_PINS_COUNT\s+(\d+)', text)
    if count and len(pins) != int(count.group(1)):
        raise SystemExit(f'解析出的管脚数 {len(pins)} 与日志自报的 {count.group(1)} 不一致，'
                         '解析器有问题，不能拿去核对分组')
    OUT_JSON.write_text(json.dumps(pins, indent=1, sort_keys=True), encoding='utf-8')
    print(f'输出 {OUT_JSON.relative_to(REPO)}（{len(pins)} 个管脚）')

    # 与本工程手册管脚表交叉核对：每个 byte lane 的 DQ/DQS/DM 是否同 Group
    pinmap = json.loads((REPO / 'tmp/ddr3/pinmap_manual.json').read_text(encoding='utf-8'))
    lines = ['# DDR3 byte lane 的物理 Group 核对（按 MES50HP 手册管脚）', '',
             'DDR3 PHY 要求同一条 lane 的 DQ[7:0]/DQS/DM 落在**同一个 I/O Group**，',
             '否则布局阶段报 `Place-0054 ... must be constrained in same DQS group`。', '']
    all_ok = True
    for lane in range(4):
        names = ([f'mem_dq[{lane*8+i}]' for i in range(8)] +
                 [f'mem_dqs[{lane}]', f'mem_dqs_n[{lane}]', f'mem_dm[{lane}]'])
        info = []
        for nm in names:
            pin = pinmap[nm]['pin']
            g = pins.get(pin, {}).get('group', '(未找到)')
            info.append((nm, pin, g))
        groups = {g for _, _, g in info}
        ok = len(groups) == 1
        all_ok &= ok
        lines += [f'## lane {lane}: {"一致" if ok else "**不一致**"} → Group {sorted(groups)}', '',
                  '| 信号 | 管脚 | Group |', '|---|---|---|']
        lines += [f'| `{nm}` | {pin} | {g} |' for nm, pin, g in info]
        lines += ['']
    lines += ['## 结论', '',
              f'- 四条 lane **{"全部" if all_ok else "并非全部"}**落在同一 Group 内。']
    OUT_MD.write_text('\n'.join(lines), encoding='utf-8')
    print(f'输出 {OUT_MD.relative_to(REPO)}')
    print('四条 lane 是否都在同一 Group:', '是' if all_ok else '否（需要按 Group 重排约束）')

    # 覆盖缺口必须显式报出来：探测没问到的管脚不能被当成"不在 B3"。
    unknown = sorted({pinmap[nm]['pin'] for nm in pinmap
                      if pinmap[nm]['pin'] not in pins})
    print(f'探测覆盖: 包内问到 {len(pins)} 个管脚；'
          f'手册 71 个管脚里有 {len(unknown)} 个没被问到')
    if unknown:
        print('  未覆盖:', ' '.join(unknown))


if __name__ == '__main__':
    main()
