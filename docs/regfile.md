# Register File Interface and Timing

## Scope

`rtl/regfile.v` implements the RV32I integer register file.  It contains 32
registers of 32 bits and exposes two read ports and one write port.  It has no
reset port: RV32I only architecturally defines `x0`; software must initialize
other registers before use.

## Interface

| Signal | Direction | Meaning |
|---|---|---|
| `clk` | input | Write clock; data is stored on its rising edge. |
| `rs1_addr`, `rs2_addr` | input [4:0] | Source register indices. |
| `rs1_data`, `rs2_data` | output [31:0] | Combinational source values. |
| `rd_addr` | input [4:0] | Destination register index. |
| `rd_data` | input [31:0] | Value to be written. |
| `rd_we` | input | Write enable. |

## Timing and `x0` contract

- A write occurs only on a rising `clk` edge when `rd_we=1` and `rd_addr!=0`.
- Reads are combinational.  Before the writing edge, a read of the destination
  returns its old value; after the edge, it returns its newly stored value.
- A write targeting `x0` is ignored.  Reading address zero from either port
  always returns `32'h0000_0000`.

## Verification

Run the independent testbench from the repository root.  The script supplies
the OSS CAD Suite `bin` and `lib` paths needed by the Windows `vvp` runtime;
it changes no persistent system environment variables.

```powershell
.\scripts\run_regfile_tb.ps1
```

The testbench covers `x1`, `x31`, two simultaneous reads, `x0` protection,
read-before/read-after-write timing, and consecutive writes.
