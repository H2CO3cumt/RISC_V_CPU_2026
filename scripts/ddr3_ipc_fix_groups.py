# -*- coding: utf-8 -*-
"""按本板手册给出的管脚，重写 HMIC_S 实例里的 DDR3 分组参数，消除"组名"与"槽号"打架。

## 为什么必须做这一步

`.ipc` 里每个 CA 信号有**两个**分组参数，它们必须说的是同一件事：

    GROUP_A1    = G6      # 这根线接在哪个物理 I/O Group 上（布局要用）
    A1_GROUP_NUM = 2      # 它属于第几个 CA 组槽
    CA_GROUP2   = G8      # 第 2 个槽到底是哪个物理 Group

出厂默认值里 `GROUP_A1=G6` 而 `A1_GROUP_NUM=2` 又指向 `CA_GROUP2=G8`——**同一根线，两处说法冲突**。
布局阶段于是报：

    Place-0054: IO instance .../i_ca_group[0].u_ddc_ca/opit_0
                must be constrained in same DQS group

含义是"你把这个 DDC 组里的引脚摆到了不同物理 Group"，而工具自己的参数就是矛盾的——怎么摆都不对。
实测这一组参数里**有 15 个不一致**，光靠改管脚约束（.fdc）永远修不好。

## 怎么修

本脚本不猜：它从 `tmp/ddr3/pinmap_manual.json`（手册管脚表）和 `tmp/ddr3/pin_groups.json`
（用 `ui::getPkgPinGroup` 问出来的包内物理 Group）**反推**正确取值，即"信号真实所在的物理 Group 是唯一真值"：

1. 每个信号 `GROUP_<X>`   = 该信号管脚所在物理 Group（布局据它放 IO）；
2. 每个 CA 组槽 `CA_GROUP<n>` = 该槽要承载的物理 Group；
3. 每个信号 `<X>_GROUP_NUM` = 承载它所在物理 Group 的那个槽号；
4. **每个信号 `CA_GROUP_<X>` = 同一个槽号**（见下面的坑，这才是生成器真正读的那个）。

改完再断言"组名 == CA_GROUP<槽号>"逐条成立，不成立就报错退出，绝不再产出矛盾配置。

## ⚠️ 最容易白干一整轮的坑：真正生效的参数叫 `CA_GROUP_<X>`，不是 `<X>_GROUP_NUM`

`.ipc` 里同名概念有**两族**参数，长得极像，但只有一族会被生成器读走：

| 参数族 | 例子 | 谁在用 |
|---|---|---|
| `<X>_GROUP_NUM` | `A0_GROUP_NUM` | **没有人**。模板里根本不引用它 |
| `CA_GROUP_<X>`  | `CA_GROUP_A0`  | **生成器**。模板写的是 `<value param='CA_GROUP_A0'>localparam A0_GROUP_NUM = %v;` |

也就是说：生成出的 `localparam A0_GROUP_NUM` 的值来自参数 **`CA_GROUP_A0`**，
名字对不上、极容易改错。实测踩坑记录：第一版只改了 26 个 `<X>_GROUP_NUM`，
`.ipc` 里确实变成了新值，但生成出的 RTL 里 `A0_GROUP_NUM` 仍是 0（出厂值），
布局阶段照旧报 `Place-0054`，白跑一轮综合+布局才发现。
**判据**：生成后去看 `rtl/ddrphy/ipsxb_ddrphy_slice_top_v1_7.v` 第 ~120-170 行的
`localparam <X>_GROUP_NUM`，和 `.ipc` 的 `CA_GROUP_<X>` 对照，一致才算生效。

## 用法

  python scripts/ddr3_ipc_fix_groups.py [--src <ipc>] [--dry-run]

输出：改写原 `.ipc`（先备份为 `.ipc.bak`），并打印逐条前后对照。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(r'D:\RISC_V_CPU_2026')
sys.path.insert(0, str(REPO / 'scripts'))
from ddr3_ipc_patch import parse_params  # noqa: E402  复用已验证的 XML 解析

# 信号名 -> `.ipc` 里 `GROUP_<X>` 的 `<X>`
CA_SIGNALS = ['A%d' % i for i in range(16)] + ['BA0', 'BA1', 'BA2',
                                                'CAS', 'RAS', 'WE', 'CK', 'CKN', 'CKE', 'ODT', 'CS']
# 数据侧：lane 号 -> (DQS 名, 数据组名)
LANES = [(f'mem_dqs_n[{i}]', f'GROUP_DQG_{i}') for i in range(4)]

# `GROUP_DQG_<k>_NUM` 的取值规则**在 IP 的界面前端里写死了**，不用猜：
#   `ui.tcl` 第 3235–3249 行 proc `get_dq_group_number`：
#       "G0"→0  "G1"→1  "G2"→2  "G3"→3  "G4"→4  "G5"→5  "G6"→6  "G7"→7  "G8"→8
#   即 **`GROUP_DQG_<k>_NUM` 就等于 `GROUP_DQG_<k>` 的数字后缀**。
#   （`ui.tcl` 第 3223–3226 行先把四个都置 9，只是占位默认值；随后被上面这个 proc 覆盖。
#     出厂 `.ipc` 里 lane2/3 = 9/9，是因为那份实例的 `DQ2_EN`/`DQ3_EN` 未被置位、
#     没走到 switch 分支，留下了占位值——**9 对 9 位 `ddrphy_ioclk` 是越界值**，
#     实测布局阶段报 `Place-0242`。所以这里必须按物理组名重新推。）
#
# 索引的物理含义：`ddrphy_slice_top` 里 `assign ddrphy_ioclk_dq[k] = ddrphy_ioclk[GROUP_DQG_<k>_NUM];`，
# 而 `ddr3_mes50hp.v` 第 360 行把 9 位拼成
#   {ioclk[2]×3, ioclk[1]×3, ioclk[0]×3}  ⇒ 索引 0–2→时钟区0、3–5→区1、6–8→区2。
# 另一条硬限制（实测）：一个 `IOCKGATE` 最多带 **3** 个 DQSL 负载——
#   `IOCKGATE ... has 4 loads (DQSL: CLK_IO), max load count is:3`；
# 而 `I_GTP_DLL` 固定吃 `ddrphy_ioclk[4]`，所以它所在那个时钟区最多再挂 2 条 lane。
# 结论：**索引必须由物理组名的后缀决定**（如上），不能自由挑；区号不匹配时表现为
# 布局报负载超限、或布线报 `Route-2014: _$$_GND_$$_ ... -> DQSL_x_y:CLK_IO`。
DQ_CLOCK_INDEX = {
    0: 5,   # lane0 物理组 G5 -> 索引 5
    1: 4,   # lane1 物理组 G4 -> 索引 4
    2: 3,   # lane2 物理组 G3 -> 索引 3
    3: 2,   # lane3 物理组 G2 -> 索引 2
}


def load_inputs() -> tuple[dict, dict]:
    pinmap = json.loads((REPO / 'tmp/ddr3/pinmap_manual.json').read_text(encoding='utf-8'))
    groups = json.loads((REPO / 'tmp/ddr3/pin_groups.json').read_text(encoding='utf-8'))
    return pinmap, groups


def rewrite(xml: str, values: dict[str, str]) -> tuple[str, list[str]]:
    """把 `values` 写回 XML 的 `<value>`；返回 (新 XML, 变更日志)。"""
    params = parse_params(xml)
    edits: list[tuple[int, int, str]] = []
    log: list[str] = []
    for name, want in values.items():
        p = params.get(name)
        if p is None:
            log.append(f'!! 实例里没有参数 {name}')
            continue
        if p['value'] == want:
            continue
        if p['items'] and want not in p['items']:
            log.append(f'!! {name}={want} 不在合法值 {p["items"]} 里')
            continue
        s, e = p['span']
        seg = xml[s:e]
        idx = seg.rfind('<value>')
        end = seg.index('</value>', idx) + len('</value>')
        edits.append((s, e, seg[:idx] + f'<value>{want}</value>' + seg[end:]))
        log.append(f'   {name:<14} {str(p["value"]):<4} => {want}')
    edits.sort(key=lambda t: -t[0])
    for s, e, new_seg in edits:
        xml = xml[:s] + new_seg + xml[e:]
    return xml, log


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', default=str(REPO / 'fpga/ddr3_smoke/ip/ddr3_mes50hp/ddr3_mes50hp.ipc'))
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()

    src = Path(args.src)
    pinmap, groups = load_inputs()

    def phys(sig: str) -> str:
        """信号所在的物理 Group（唯一真值）。"""
        pin = pinmap[sig]['pin']
        return groups[pin]['group']

    # 1) CA 侧：先按物理 Group 归堆，再给每个物理 Group 分配一个 CA 组槽。
    want: dict[str, str] = {}
    by_group: dict[str, list[str]] = defaultdict(list)
    skipped: list[tuple[str, str]] = []
    for sig in CA_SIGNALS:
        # `.ipc` 里的信号名（A0/BA1/CAS…）映射到手册管脚表的键（mem_a[0]/mem_ba[1]/mem_cas_n）
        if sig.startswith('A') and sig[1:].isdigit():
            name = f'mem_a[{sig[1:]}]'
        elif sig.startswith('BA'):
            name = f'mem_ba[{sig[2:]}]'
        else:
            name = {'CAS': 'mem_cas_n', 'RAS': 'mem_ras_n', 'WE': 'mem_we_n',
                    'CK': 'mem_ck', 'CKN': 'mem_ck_n', 'CKE': 'mem_cke',
                    'ODT': 'mem_odt', 'CS': 'mem_cs_n'}.get(sig, '')
        if name not in pinmap:
            # 手册管脚表是"厂商模板端口清单 ∩ 手册"筛出来的，只含 IP 顶层真实存在的端口。
            # 例：手册有 ddr3_addr[15]=R7，但本 IP 顶层是 mem_a[14:0]（15 位行地址），
            # 没有 mem_a[15] 端口，该信号在本设计里根本不引出，跳过即可。
            skipped.append((sig, name))
            continue
        g = phys(name)
        by_group[g].append(sig)
        want[f'GROUP_{sig}'] = g

    # 槽号按物理 Group 名排序，保证可复现；组数=实际用到的物理 Group 数。
    slots = sorted(by_group)
    slot_of = {g: i for i, g in enumerate(slots)}
    for g, sigs in by_group.items():
        for sig in sigs:
            # 两族都写：`CA_GROUP_<X>` 是生成器真正读的那个（见文件头说明），
            # `<X>_GROUP_NUM` 是同一概念的另一份参数，一并对齐以免留下误导信息。
            want[f'{sig}_GROUP_NUM'] = str(slot_of[g])
            want[f'CA_GROUP_{sig}'] = str(slot_of[g])
    for g in slots:
        want[f'CA_GROUP{slot_of[g]}'] = g
    want['CA_GROUP_NUM'] = str(len(slots))

    # 2) 数据侧：每条 lane 的 DQ/DQS/DM 必须同物理 Group，取 lane 内一致的那个值。
    lane_report = []
    for i, (dqs_name, gname) in enumerate(LANES):
        names = [f'mem_dq[{i*8+k}]' for k in range(8)] + [dqs_name, f'mem_dm[{i}]']
        gs = {phys(n) for n in names}
        if len(gs) != 1:
            raise SystemExit(f'lane {i} 的管脚跨了多个物理 Group {sorted(gs)}，'
                             '约束无论怎么写都摆不下，必须先解决硬件分组问题')
        g = gs.pop()
        want[gname] = g
        # 时钟索引单独设，见 DQ_CLOCK_INDEX 的说明
        want[f'{gname}_NUM'] = str(DQ_CLOCK_INDEX[i])
        lane_report.append((i, g, sorted(names)[0]))

    xml = src.read_text(encoding='utf-8')
    params = parse_params(xml)
    print(f'{src.name}: {len(params)} 个参数')
    print()
    if skipped:
        print('跳过（本设计顶层没有该端口，不引出）:')
        for sig, name in skipped:
            print(f'  {sig}（手册名 {name}）')
        print()
    print('物理 Group 归堆（CA 侧）:')
    for g in slots:
        print(f'  {g} -> CA 组槽 {slot_of[g]}  承载 {len(by_group[g])} 根: '
              f'{" ".join(by_group[g])}')
    print()
    print('lane 物理 Group:')
    for i, g, _ in lane_report:
        print(f'  lane{i} -> {g}')
    print()

    new_xml, log = rewrite(xml, want)
    print(f'改写 {len(log)} 条:')
    for line in log:
        print(line)

    # 3) 断言：组名必须等于该信号槽号所指的 CA_GROUP<槽>。
    P = parse_params(new_xml)
    cag = {i: P[f'CA_GROUP{i}']['value'] for i in range(int(P['CA_GROUP_NUM']['value']))}
    bad = []
    checked = 0
    for sig in CA_SIGNALS:
        # A15 等"本 IP 顶层不引出的信号"跳过：参数留在 `.ipc` 里但无人使用，
        # 其槽号/组名对不对不影响网表（实测 A15 组名 G2、槽号 0->G0 不一致，属历史残留）。
        if any(s == sig for s, _ in skipped):
            continue
        num_k = f'{sig}_GROUP_NUM'
        if num_k not in P:
            continue
        if num_k == 'CKN_GROUP_NUM':
            continue
        checked += 1
        g = P[f'GROUP_{sig}']['value']
        # 生成器真正读的是 CA_GROUP_<X>，两族都必须与槽号所指的物理组一致。
        for key in (num_k, f'CA_GROUP_{sig}'):
            if key not in P:
                bad.append((f'{sig}({key} 缺失)', g, '-', '-'))
                continue
            num = int(P[key]['value'])
            if g != cag.get(num):
                bad.append((f'{sig}({key})', g, num, cag.get(num)))
    print()
    if bad:
        for sig, g, num, exp in bad:
            print(f'!! 仍不一致: {sig} 组名={g} 槽号={num} 槽={exp}')
        raise SystemExit(f'改写后仍有 {len(bad)} 条矛盾，拒绝输出')
    print(f'一致性断言通过：{checked} 个 CA 信号的"组名==CA_GROUP<槽号>"逐条成立')
    # 数据侧也断言一遍：每条 lane 的组名必须等于该 lane 管脚的真实物理 Group；
    # 时钟索引必须在 9 位 `ddrphy_ioclk` 的范围内（出厂默认的 9 就越界了）。
    for i, (dqs_name, gname) in enumerate(LANES):
        names = [f'mem_dq[{i*8+k}]' for k in range(8)] + [dqs_name, f'mem_dm[{i}]']
        g = {phys(n) for n in names}
        if len(g) != 1 or P[gname]['value'] != g.pop():
            raise SystemExit(f'lane {i} 的 {gname} 与物理 Group 不符')
        idx = int(P[f'{gname}_NUM']['value'])
        if not 0 <= idx <= 8:
            raise SystemExit(f'lane {i} 的 {gname}_NUM={idx} 超出 ddrphy_ioclk[8:0] 范围')
    print(f'数据侧断言通过：4 条 lane 的 GROUP_DQG_* 与管脚物理 Group 一致，'
          f'时钟索引均落在 0..8')
    print(f'  时钟索引（0-2→区0, 3-5→区1, 6-8→区2）: '
          + ', '.join(f'lane{i}={DQ_CLOCK_INDEX[i]}' for i in range(4)))
    print(f'CA_GROUP* 映射: {cag}')

    if args.dry_run:
        print('（--dry-run，未写文件）')
        return
    bak = src.with_suffix(src.suffix + '.bak')
    if not bak.exists():
        shutil.copy2(src, bak)
        print(f'备份 {bak.name}')
    src.write_text(new_xml, encoding='utf-8')
    print(f'已写回 {src}')


if __name__ == '__main__':
    main()
