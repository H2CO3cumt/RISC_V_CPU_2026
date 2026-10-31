# 离线回放样本（第 ② 页「CPU 数据流」用）

本目录只有一份数据文件 `trace_hello_rv.log`：第 ② 页在没有开发板时回放的那一枪真实记录。
它是 `release/evidence/trace85_board/trace_phase0.log` 的**逐字节副本**，不是另录的、也不是造的。

## 1. 这一枪是什么

| 项 | 值 |
|---|---|
| 采集场合 | MES50HP 实体板，`trace85` 工程（85 MHz PLL），串口 COM11 |
| 采集日期 | 2026-10-24 |
| 发送给 CPU 的字符串 | `hello,rv`（8 个字符） |
| 记录条数 / 打点数 / 状态 | 100 / 8 / `status=0x4`（done=1，未溢出） |
| PC 种类 | 19 |
| 本文件 SHA-256 | `46E05077478BFD5C6044FFCECBD59A77F1ABE4E35CC5CF58A4890964A05FC016` |
| 来源证据 SHA-256 | 同上（`release/evidence/trace85_board/trace_phase0.log`） |

`release/evidence/trace85_board/` 里还有一枪 `trace_phase1.log`（4096 条写满窗口、含串口轮询），
本目录**不放**它：第 ② 页默认的阶段 0 判据不适用于它，放进来只会让人误判。

## 2. 必须跟哪份程序镜像配对

回放会把记录里的 PC 拿去和**当前**固件镜像逐条对拍（判据 `pc 与位流镜像同源`），
所以样本与镜像是一对，换一个就错：

| 配对项 | 值 |
|---|---|
| 镜像文件 | `fpga/trace85/rtl/logic_analyzer_program.mem` |
| 镜像 SHA-256 | `7C45D16DB5AD12A39747AB0BAC88B8B7E83E9918694F8444E4B76AB0C0F64F78` |
| 2026-10-28 复核结果 | **15 / 15 PASS**，其中 `pc 与位流镜像同源` 不一致 **0** 条 |

> **纪律**：只要 `fpga/trace85/rtl/logic_analyzer_program.mem` 重新生成过，
> 这份样本就**必须重录**（板上再采一枪）或重新对齐，否则第 ② 页会把
> `pc 与位流镜像同源` 判成全错——那正是 2026-10-28 修掉的那个缺陷。
> 快速自检（只读，不需要板子）：
>
> ```powershell
> cd python; python -c "import trace_view as tv; from pathlib import Path; cap=tv.parse_capture(Path('samples/trace_hello_rv.log').read_bytes().decode('utf-8','replace')); sent=''.join(chr(m['value']) for m in cap['marks']); im=tv.load_program_mem(Path('../fpga/trace85/rtl/logic_analyzer_program.mem')); r=tv.judge(cap,sent,0,im,depth=4096); print('PASS' if tv.judgements_pass(r) else 'FAIL', [n for n,ok,_ in r if not ok])"
> ```

## 3. 判据口径（踩过的坑）

`judge()` 的 `sent_text` 要的是**当时真正送进 CPU 的原始字节**，也就是打点值：

```python
sent = "".join(chr(m["value"]) for m in capture["marks"])   # 正确：'hello,rv'
```

**不能**用回包里的 `TRACE TEXT` 字段：那是固件处理**之后**的结果（阶段 0 已把小写转成大写，
这里是 `HELLO,RV`）。拿它去判据会稳定产生 2 条假 FAIL：

| 判据 | 用打点（正确） | 用 `TRACE TEXT`（错误） |
|---|---|---|
| `打点值等于发送的字符` | PASS | FAIL（打点=`hello,rv`，发送=`HELLO,RV`） |
| `大写字符计数` | PASS（up=7） | FAIL（大写的文本里没有小写字母，期望 up=0） |

## 4. 历史（2026-10-28 修复）

替换前的旧样本是 **2026-10-23** 那一枪，比当前镜像**整体低 0x434 字节**
（同一批指令的 PC 从 `0x998` 变成 `0xDCC`）。用当前镜像反汇编旧样本，
100 条记录的 PC **全部对不上**，于是双击打开第 ② 页时状态栏是 `FAIL`。
现样本与 `release/evidence/trace85_board/trace_phase0.log` 逐字节一致，
并已在 `scripts/run_final_regression.ps1` 之外的独立自检中跑过 15/15 PASS。
