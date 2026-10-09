#!/bin/sh
# CoreMark Makefile 的 PowerShell 宿主桥。
#
# 为什么需要它：Makefile 的 check-isa 目标要跑 scripts/check_coremark_elf.ps1，
# 但 `make.exe` 不能直接执行 .ps1。本机没有 PowerShell 7（`pwsh` 不在 PATH），
# 而 Windows PowerShell 5.1 装在 System32\WindowsPowerShell\v1.0 且该目录也不在
# PATH 里。这里按 pwsh → powershell → 固定路径的顺序挑一个可用宿主，
# 把参数原样转发，并把退出码带回去，保证 make 能正确判定 PASS/FAIL。
#
# 用法与原来的 `pwsh -NoProfile -File <script> <args...>` 等价：
#   sh scripts/run_check_coremark_elf.sh -Disassembly <dis> -Attributes <attr>
# 目标脚本固定为本文件同目录下的 check_coremark_elf.ps1，位置由 $0 推出，
# 因此从 CoreMark 的 Makefile（工作目录是 software/coremark）调用也能找到。

SELF_DIR=$(dirname "$0")
TARGET="$SELF_DIR/check_coremark_elf.ps1"
if [ ! -f "$TARGET" ]; then
    echo "CHECK CORE ELF FAIL: missing $TARGET" >&2
    exit 1
fi

if command -v pwsh >/dev/null 2>&1; then
    HOST=pwsh
elif command -v powershell >/dev/null 2>&1; then
    HOST=powershell
elif [ -x "/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
    HOST="/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
elif [ -x "$SYSTEMROOT/System32/WindowsPowerShell/v1.0/powershell.exe" ]; then
    HOST="$SYSTEMROOT/System32/WindowsPowerShell/v1.0/powershell.exe"
else
    echo "CHECK CORE ELF FAIL: no PowerShell host found (pwsh / powershell)" >&2
    exit 1
fi

"$HOST" -NoProfile -ExecutionPolicy Bypass -File "$TARGET" "$@"
exit $?
