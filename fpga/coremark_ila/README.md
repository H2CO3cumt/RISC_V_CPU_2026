# Task 29 CoreMark PDS DebugCore

This diagnostic build is separate from the formal Task 28 score build so the
DebugCore does not change the published area/Fmax figures. It uses the same
CoreMark image and the same MES50HP pins.

The single 192-bit DebugCore trigger/data port is sampled at 50 MHz with 512
samples. Probe fields are:

| Bits | Signal |
|---:|---|
| 0 | retired instruction valid |
| 32:1 | retired PC |
| 64:33 | retired instruction |
| 65 | register write enable |
| 70:66 | destination register |
| 102:71 | register write data |
| 103 | committed memory write |
| 135:104 | committed memory address |
| 167:136 | committed memory data |
| 171:168 | committed memory byte strobes |
| 172 | pipeline stall event |
| 173 | load-use stall event |
| 174 | branch event |
| 175 | branch taken event |
| 176 | flush event |
| 177 | synchronous CPU reset |
| 178 | data request valid |
| 179 | data request ready |
| 180 | instruction request valid |
| 181 | instruction request ready |
| 182 | initialized memory ready |
| 191:183 | reserved zero |

Run `scripts/run_coremark_ila_pds.ps1`. Download the generated diagnostic `.sbit`,
open Fabric Debugger, select `coremark_ila`, and trigger on bit 0 (retirement)
or bits 174/176 (branch/flush). The formal performance figures remain those
from `fpga/coremark`.
