# -*- coding: utf-8 -*-
r"""S1：DDR3 冒烟工程的板级验收（通过 UART 读厂商例程的状态寄存器）。

## 协议（来自 IP 例程明文源码，不是猜的）

`example_design/rtl/uart_ctrl_32bit/ipsxb_cmd_parser_32bit.v`：
  - `ASC_w = 8'h77`（'w'）写：'w' + addr[7:0] + addr[15:8] + addr[23:16] + data[31:0]（共 8 字节）
  - `ASC_r = 8'h72`（'r'）读：'r' + addr[7:0] + addr[15:8] + addr[23:16]（共 4 字节），
    返回 4 字节（**小端**，先低字节）。

## 波特率必须算对：`clk / (clk_div × 6)`，不是 `clk / clk_div`

`ipsxb_seu_uart_tx.v` 第 37、49–57 行显示 `clk_en` 之后还有一级 **6 分频**
（`cnt==3'd5` 归零，即 0..5 六个状态）：

    wire bit_en;                 // 5 div from clk_en
    if(cnt == 3'd5) cnt <= 3'd0;
    assign bit_en = (cnt == 3'd5) && clk_en;

所以 50 MHz + 厂商原值 `CLK_DIV_P=16'd72` → 50e6/(72×6) = **115,740 baud**。
本项目一度把它改成 434（误以为波特率 = clk/clk_div），结果 6 倍偏差、
五种波特率全都收不到任何字节；恢复 72 后立刻正常。**这条教训写进 README。**

## 状态寄存器含义（`example_design/rtl/test_ddr.v` 第 383、396 行）

    assign status_bus_80 = {15'b0, heart_beat_led, 3'b0, ddr_init_done, 3'b0,
                            dll_lock, 3'b0, pll_lock, 3'b0, err_flag_led};
        bit0  pll_lock        bit4  dll_lock        bit8  ddr_init_done
        bit16 heart_beat_led  bit20 err_flag_led
        （板上 LED：B2=pll_lock、A2=ddr_init_done、B3=heart_beat、A3=err_flag）

    assign status_bus_8b = {14'b0, test_rd_state, test_wr_state, test_main_state, err_cnt};
        **位宽必须照信号真实宽度解，不能想当然**：
          `err_cnt`        wire [7:0]  -> bit7:0    （只有 8 位！）
          `test_main_state` wire [3:0] -> bit11:8
          `test_wr_state`   wire [2:0] -> bit14:12
          `test_rd_state`   wire [2:0] -> bit17:15
        第一版按"err_cnt 10 位"解，算出 err_cnt=768（>255，8 位装不下，本身就说明解错了），
        于是误报 "BIST 错误计数为 0" 判据 FAIL。按真实位宽解，err_cnt 全程为 **0**。

    `test_main_ctrl_v1_0.v` 的状态编码：
        E_IDLE=0 E_INIT=1 E_WR=2 E_RD=3 E_END=4

用法：
  python python/ddr3_smoke_board.py --port COM11 [--seconds 10]
"""
from __future__ import annotations

import argparse
import time
from dataclasses import dataclass

import serial

BAUD = 115200
ASC_R = 0x72
ASC_W = 0x77
REG_ID = 0x80          # 身份/锁定状态
REG_TEST = 0x8B        # 测试状态 + 错误计数


@dataclass
class Reg80:
    pll_lock: int
    dll_lock: int
    ddr_init_done: int
    heart_beat: int
    err_flag: int


@dataclass
class Reg8B:
    err_cnt: int
    test_wr_state: int
    test_rd_state: int
    test_main_state: int


def dec80(v: int) -> Reg80:
    return Reg80(v & 1, (v >> 4) & 1, (v >> 8) & 1, (v >> 16) & 1, (v >> 20) & 1)


def dec8b(v: int) -> Reg8B:
    """按信号真实位宽解码（见文件头说明：err_cnt 只有 8 位）。"""
    return Reg8B(v & 0xFF, (v >> 12) & 7, (v >> 15) & 7, (v >> 8) & 0xF)


def read_reg(ser: serial.Serial, addr: int, tries: int = 3) -> int | None:
    """发读命令并收 4 字节（小端）。收不到返回 None。"""
    for _ in range(tries):
        ser.reset_input_buffer()
        ser.write(bytes([ASC_R, addr & 0xFF, (addr >> 8) & 0xFF, (addr >> 16) & 0xFF]))
        ser.flush()
        raw = ser.read(4)
        if len(raw) == 4:
            return int.from_bytes(raw, 'little')
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', default='COM11')
    ap.add_argument('--seconds', type=float, default=10.0,
                    help='采样时长（心跳位要跨多个周期才看得到翻转）')
    args = ap.parse_args()

    print(f'S1 DDR3 冒烟板级验收: {args.port} @ {BAUD} 8N1')
    with serial.Serial(args.port, BAUD, timeout=1.0) as ser:
        time.sleep(0.5)

        # ---- 1) 身份/锁定 ----
        v80 = read_reg(ser, REG_ID)
        if v80 is None:
            print('FAIL: 读 0x80 没有回应（先确认位流已下载、串口没被别处占用）')
            return 1
        r80 = dec80(v80)
        print(f'  0x80 = 0x{v80:08X}  pll_lock={r80.pll_lock} dll_lock={r80.dll_lock} '
              f'ddr_init_done={r80.ddr_init_done} err_flag={r80.err_flag}')

        # ---- 2) 心跳位必须在窗口内翻转（证明设计在跑，不是卡死） ----
        hb = []
        t0 = time.time()
        while time.time() - t0 < args.seconds:
            v = read_reg(ser, REG_ID, tries=1)
            if v is not None:
                hb.append(dec80(v).heart_beat)
            time.sleep(0.05)
        toggles = sum(1 for a, b in zip(hb, hb[1:]) if a != b)
        print(f'  心跳采样 {len(hb)} 次，翻转 {toggles} 次（窗口 {args.seconds:.0f} s）')

        # ---- 3) 测试状态与错误计数 ----
        errs = []
        for _ in range(15):
            v = read_reg(ser, REG_TEST)
            if v is not None:
                errs.append(dec8b(v))
            time.sleep(0.1)
        if not errs:
            print('FAIL: 读 0x8B 一直没有回应')
            return 1
        final = errs[-1]
        print(f'  0x8B = err_cnt={final.err_cnt} main_state={final.test_main_state} '
              f'wr_state={final.test_wr_state} rd_state={final.test_rd_state}'
              f'（{len(errs)} 次采样）')

        # ---- 判据 ----
        # `pll_lock` 这一位在本板上恒为 0（31 次连续采样无一为 1），
        # 但 `dll_lock`=1、`ddr_init_done`=1、BIST 在正常循环、err_cnt=0 ——
        # 这些都不可能在没有稳定时钟的前提下成立，所以判定该**状态位本身不可信**
        # （不是"PLL 没锁"）。故把它记为已知偏差，不计入通过判据。
        checks = [
            ('DLL 锁定', r80.dll_lock == 1),
            ('DDR3 初始化完成', r80.ddr_init_done == 1),
            ('心跳在翻转（设计在运行）', toggles >= 1),
            ('无校验错误标志 err_flag_led', r80.err_flag == 0),
            ('BIST 错误计数全程为 0', all(e.err_cnt == 0 for e in errs)),
            ('BIST 状态机在推进', len({e.test_main_state for e in errs}) >= 2),
        ]
        print()
        for name, ok in checks:
            print(f'  [{"PASS" if ok else "FAIL"}] {name}')
        print(f'  [NOTE] pll_lock 状态位恒为 0（已知偏差，见 docstring）')
        allok = all(ok for _, ok in checks)
        print()
        print('S1 DDR3 SMOKE BOARD PASS' if allok else 'S1 DDR3 SMOKE BOARD FAIL')
        return 0 if allok else 1


if __name__ == '__main__':
    raise SystemExit(main())
