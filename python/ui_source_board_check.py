"""采集源（J8 外部 / Core 内部观测点）在**真实界面路径**上的实板检查。

走的是 pyUI 自己的 `_run_logic_analyzer()`，不是另写一套采集脚本——证据要能回答
"点这个按钮会发生什么"。交互顺序按真实操作员：先选模式（面板载入该模式默认值），
再改「采集源」，最后点采集。

跑法（板子已下载交付位流并接在 COM11 上）：

    python python/ui_source_board_check.py COM11
    # 或： scripts\\run_ui_source_board.ps1 -Port COM11

四组"模式 × 采集源"组合各抓一枪，断言报文长度/命令码/[14] 源字节：
    core + Core 源 → 16 字节 0xA8，[14]=1
    uart + Core 源 → 16 字节 0xA8，[14]=1（本窗按流水线观测点解释，不做 UART 解码）
    uart + J8   源 → 13 字节 0xA5（历史路径逐字节不变）
    core + J8   源 → 13 字节 0xA5，按 raw 解释

两个坑在这里踩过，脚本必须绕开：
  1. UI 的失败路径会弹**模态对话框**等人点 OK，无人值守时会被永久挂住 → 换成记录+打印；
  2. 触发条件永不出现会把固件停住（串口不再响应，只能按 REST/重下位流恢复）→
     本脚本一律使用**必然会命中**的触发，并在真出现该症状时立刻收手不再重试。
"""
from __future__ import annotations

import queue
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

import mes50hp_validation_ui as ui_mod  # noqa: E402
from logic_analyzer_serial import SOURCE_CHOICES  # noqa: E402

# 无人值守：UI 的失败路径会弹模态对话框等人点 OK，脚本会被永久挂住。
# 把两个弹窗换成"记下来 + 打印"，其余行为一概不动（判据仍在库里）。
dialogs: list[str] = []


def _fake_box(title, message, *a, **k):
    dialogs.append("%s: %s" % (title, message))
    print("  [dialog] %s: %s" % (title, message))


ui_mod.messagebox.showerror = _fake_box
ui_mod.messagebox.showinfo = _fake_box

PORT = sys.argv[1] if len(sys.argv) > 1 else "COM11"
J8 = SOURCE_CHOICES[0][0]
CORE = SOURCE_CHOICES[1][0]

app = ui_mod.ValidationUI()
app.withdraw()
app.port_var.set(PORT)
app.runs_var.set("1")
app.timeout_var.set("20")
app.output_var.set(str(ROOT / "results" / "ui_board_check"))
app.manual_var.set(True)
app.live_var.set(False)

failures: list[str] = []
checks: list[str] = []
settled = False
board_dead = False
dialogs: list[str] = []
packets: list[str] = []
KEEP = ("报文", "PASS", "FAIL", "全部模式", "提示", "错误")


def drain(tag: str) -> None:
    global settled, board_dead
    while True:
        try:
            kind, payload = app.events.get_nowait()
        except queue.Empty:
            return
        if kind == "log":
            for line in str(payload).splitlines():
                line = line.strip()
                if not line:
                    continue
                if "报文" in line:
                    packets.append(line.split("报文", 1)[1].split("·", 1)[0].strip())
                if any(k in line for k in KEEP):
                    print("    " + line)
        elif kind == "done":
            print("  [%s] %s" % (tag, payload))
            settled = True
        elif kind == "error":
            print("  [%s] %s" % (tag, payload))
            failures.append("%s: %s" % (tag, payload))
            if "板子完全没有输出" in str(payload):
                # 固件停在等待采集完成，串口不再响应：后面每一枪都会白等 20 秒，
                # 而且必须重新下载位流才能恢复。立刻收手，别把时间烧在重试上。
                board_dead = True
            settled = True
        elif kind == "wave":
            samples, trigger, info = payload
            print("  [%s] wave mode=%s samples=%d trigger=%d" % (tag, info.get("mode"), len(samples), trigger))


def expect(what: str, got, want) -> None:
    ok = got == want
    checks.append("%-46s %-26s %s" % (what, got, "OK" if ok else "FAIL want=%s" % (want,)))
    if not ok:
        failures.append("%s: got %s want %s" % (what, got, want))


def packet_field(packet: str, index: int) -> int:
    return int(packet[2 * index:2 * index + 2], 16)


def run(tag: str, mode: str, source_label: str | None, want_len: int, want_src: int,
        tune=None) -> None:
    print("== %s: mode=%s source=%s ==" % (tag, mode, source_label))
    app.live_mode_var.set(mode)
    app._on_mode_change()  # 真实顺序：先选模式，面板载入该模式默认值
    if source_label is not None and app.knob_vars["source"].get() != source_label:
        app.knob_vars["source"].set(source_label)
        app._on_source_change()
    if tune:
        tune()
    print("  panel: source=%s sample_div=%s pre=%s post=%s mask=%s type=%s level=%s"
          % (app.knob_vars["source"].get(), app.knob_vars["sample_div"].get(),
             app.knob_vars["pre"].get(), app.knob_vars["post"].get(),
             app.knob_vars["trigger_channel"].get(), app.knob_vars["trigger_type"].get(),
             app.knob_vars["trigger_level"].get()))
    expect("%s 面板采集源" % tag, app.knob_vars["source"].get(), source_label or CORE if mode == "core" else (source_label or J8))
    packets.clear()
    app.running = False
    app._run_logic_analyzer()
    global settled
    settled = False
    deadline = time.monotonic() + 90
    # 完成信号取 app.running：UI 自己的 _poll_events 收到 done/error 时会复位它。
    # 不能只等我自己从队列里抢到 done —— 队列是两边共用的，谁先取到是随机的。
    while app.running and not settled and time.monotonic() < deadline:
        app.update()
        drain(tag)
        time.sleep(0.05)
    app.update()
    drain(tag)
    if app.running and not settled:
        failures.append("%s: timeout" % tag)
        print("  [%s] TIMEOUT" % tag)
        return
    if not packets:
        failures.append("%s: 没有解析到报文" % tag)
        return
    packet = packets[-1].replace(" ", "")
    expect("%s 报文长度" % tag, len(packet) // 2, want_len)
    if len(packet) // 2 != want_len:
        return
    expect("%s 命令码" % tag, hex(packet_field(packet, 0)), hex(0xA8 if want_len == 16 else 0xA5))
    if want_len == 16:
        expect("%s [14] 采集源" % tag, packet_field(packet, 14), want_src)


def tune_j8_trigger() -> None:
    """core 预设等的 ch6 上升沿在 J8 源下是根外部引脚，没信号就永远等不到；
    这里按操作员会做的事把触发挪到 ch0 的电平触发（上电即为低，立刻命中）。"""
    app.knob_vars["trigger_channel"].set("ch0")
    app.knob_vars["trigger_type"].set("level")
    app.knob_vars["trigger_level"].set("0 低")
    app._update_knob_info()


def display_only(mode: str, want: str) -> None:
    app.manual_var.set(False)
    app.live_mode_var.set(mode)
    app._on_mode_change()
    got = app.knob_vars["source"].get()
    app.manual_var.set(True)
    expect("不勾面板时 %s 显示采集源" % mode, got, want)


try:
    display_only("core", CORE)
    display_only("uart", J8)
    for tag, args, kwargs in (
            ("A core 默认(Core 源)", ("core", None, 16, 1), {}),
            ("B uart 切 Core 源", ("uart", CORE, 16, 1), {}),
            ("C uart 默认(J8 源)", ("uart", None, 13, 0), {}),
            ("D core 切回 J8 源", ("core", J8, 13, 0), {"tune": tune_j8_trigger})):
        if board_dead:
            print("== 跳过 %s：板子已停在等待采集完成，需重新下载位流才能继续 ==" % tag)
            failures.append("%s: 跳过（板子需重新下载位流）" % tag)
            break
        run(tag, *args, **kwargs)
finally:
    try:
        app.destroy()
    except Exception:
        pass

print()
for line in checks:
    print("  " + line)
for item in dialogs:
    print("  [dialog] " + item)
print()
if failures or dialogs:
    print("UI BOARD CHECK FAIL:")
    for item in failures + dialogs:
        print("  - " + item)
    sys.exit(1)
print("UI BOARD CHECK PASS")
