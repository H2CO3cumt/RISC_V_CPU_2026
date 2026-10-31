param(
  [Parameter(Mandatory=$true)][string]$Disassembly,
  [Parameter(Mandatory=$true)][string]$Attributes,
  # 期望的 ELF 架构属性。默认 rv32i2p1 = 赛题与项目固定的基线口径；
  # 构建 M 扩展镜像时传 rv32im2p1，此时还额外要求反汇编里**真的**出现
  # 硬件 M 指令（否则可能是拿 rv32i 镜像冒充 rv32im）。
  [string]$ExpectArch = 'rv32i2p1'
)
$ErrorActionPreference='Stop'
$dis=Get-Content -Raw -LiteralPath $Disassembly
$attr=Get-Content -Raw -LiteralPath $Attributes
$mMatches=[regex]::Matches($dis,'(?m)^\s*[0-9a-f]+:\s+[0-9a-f]+\s+(mul|mulh|mulhsu|mulhu|div|divu|rem|remu)\b')
if($ExpectArch -eq 'rv32i2p1'){
  if($mMatches.Count -gt 0){
    throw "COREMARK ISA CHECK FAIL: hardware M instruction '$($mMatches[0].Groups[1].Value)' found in an RV32I image"
  }
  if($attr -notmatch 'Tag_RISCV_arch:\s+"rv32i2p1"'){
    throw 'COREMARK ISA CHECK FAIL: ELF attribute is not exactly rv32i2p1'
  }
  Write-Host 'COREMARK ISA CHECK PASS: RV32I-only ELF (software helpers allowed)'
}
else{
  if($mMatches.Count -eq 0){
    throw "COREMARK ISA CHECK FAIL: $ExpectArch image contains no hardware M instruction"
  }
  $archMatch=[regex]::Match($attr,'Tag_RISCV_arch:\s+"([^"]+)"')
  if(-not $archMatch.Success){
    throw 'COREMARK ISA CHECK FAIL: ELF has no Tag_RISCV_arch attribute'
  }
  $arch=$archMatch.Groups[1].Value
  # GCC 会把 -march=rv32im 规范化成 rv32i2p1_m2p0_zmmul1p0（M = Zmmul + 除法），
  # 具体串随 GCC 版本略有差别（有的只写到 m2p0），因此按基线前缀判定，
  # 而不是写死一整串——否则换个工具链版本就会莫名其妙地失败。
  if($ExpectArch -eq 'rv32im2p1'){
    if($arch -notmatch '^rv32i2p1_m2p0'){
      throw "COREMARK ISA CHECK FAIL: ELF attribute '$arch' is not an RV32IM baseline"
    }
  }
  elseif($arch -ne $ExpectArch){
    throw "COREMARK ISA CHECK FAIL: ELF attribute '$arch' is not exactly $ExpectArch"
  }
  Write-Host "COREMARK ISA CHECK PASS: $arch ELF with $($mMatches.Count) hardware M instructions"
}
