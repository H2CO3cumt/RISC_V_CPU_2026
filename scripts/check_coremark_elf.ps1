param(
  [Parameter(Mandatory=$true)][string]$Disassembly,
  [Parameter(Mandatory=$true)][string]$Attributes
)
$ErrorActionPreference='Stop'
$dis=Get-Content -Raw -LiteralPath $Disassembly
$attr=Get-Content -Raw -LiteralPath $Attributes
if($dis -match '(?m)^\s*[0-9a-f]+:\s+[0-9a-f]+\s+(mul|mulh|mulhsu|mulhu|div|divu|rem|remu)\b'){
  throw "COREMARK ISA CHECK FAIL: hardware M instruction '$($Matches[1])' found"
}
if($attr -notmatch 'Tag_RISCV_arch:\s+"rv32i2p1"'){
  throw 'COREMARK ISA CHECK FAIL: ELF attribute is not exactly rv32i2p1'
}
Write-Host 'COREMARK ISA CHECK PASS: RV32I-only ELF (software helpers allowed)'
