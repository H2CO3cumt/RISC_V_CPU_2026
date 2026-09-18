`timescale 1ns/1ps

// Task 17 evidence exporter for the pre-existing Task 14 GCC programs.
// It observes the unchanged Core through the Task 15 RAM-only SoC shell.
module tb_gcc_evidence;
`ifdef GCC_EVIDENCE_C_SMOKE
`define GCC_EVIDENCE_IMAGE "software/c_smoke/build/c_smoke_sum.mem"
    localparam [31:0] FINAL_ADDR = 32'h00000200, FINAL_DATA = 32'd45;
`elsif GCC_EVIDENCE_ARRAY_CONTROL
`define GCC_EVIDENCE_IMAGE "software/c_array_control/build/c_array_control_imem.mem"
    localparam [31:0] FINAL_ADDR = 32'h00000208, FINAL_DATA = 32'hFFFFFFFF;
`else
    initial $fatal(1, "Define a Task 14 program");
`endif
    reg clk, reset, snapshot_taken;
    integer cycles, retired, trace_file, state_file, perf_file, i;
    reg [31:0] regs [1:31];
    wire tv, rw, mw; wire [31:0] pc, inst, rd_data, mem_addr, mem_data; wire [4:0] rd; wire [3:0] wstrb;
    core_harness #(.IMEM_DEPTH(256), .DMEM_DEPTH(256), .IMEM_INIT_FILE(`GCC_EVIDENCE_IMAGE)) dut (
        .clk(clk), .reset(reset), .trace_valid(tv), .trace_pc(pc), .trace_instruction(inst), .trace_rd_we(rw), .trace_rd_addr(rd), .trace_rd_data(rd_data), .trace_mem_we(mw), .trace_mem_addr(mem_addr), .trace_mem_data(mem_data), .trace_mem_wstrb(wstrb));
    always #5 clk=~clk;
    always @(posedge clk) begin
        if (reset) begin cycles<=0; retired<=0; snapshot_taken<=0; end
        else begin
            cycles<=cycles+1;
            if (tv && !snapshot_taken) begin retired<=retired+1; $fdisplay(trace_file, "%0d %08h %08h %0d %0d %08h %0d %08h %08h %01h", retired,pc,inst,rw,rd,rd_data,mw,mem_addr,mem_data,wstrb); end
            if (tv && mw && mem_addr==FINAL_ADDR && mem_data==FINAL_DATA && !snapshot_taken) begin
                snapshot_taken<=1;
                for(i=1;i<32;i=i+1) regs[i]<=dut.core.u_regfile.regs[i];
            end
        end
    end
    initial begin
        clk=0; reset=1; cycles=0; retired=0; snapshot_taken=0;
`ifdef GCC_EVIDENCE_C_SMOKE
        trace_file=$fopen("tmp/gcc_evidence/c_smoke_trace.actual","w"); state_file=$fopen("tmp/gcc_evidence/c_smoke_state.actual","w"); perf_file=$fopen("tmp/gcc_evidence/c_smoke_perf.actual","w");
        #1; dut.ram.mem[128]=32'hDEADBEEF;
`else
        trace_file=$fopen("tmp/gcc_evidence/array_control_trace.actual","w"); state_file=$fopen("tmp/gcc_evidence/array_control_state.actual","w"); perf_file=$fopen("tmp/gcc_evidence/array_control_perf.actual","w");
        #1; $readmemh("software/c_array_control/build/c_array_control_dmem.mem",dut.ram.mem); dut.ram.mem[129]=32'hDEADBEEF; dut.ram.mem[130]=32'hCAFEBABE;
`endif
        repeat(2) @(negedge clk); reset=0; wait(snapshot_taken); @(negedge clk); #1;
        for(i=1;i<32;i=i+1) $fdisplay(state_file,"x%0d=%08h",i,regs[i]);
        $fdisplay(state_file,"ram[00000200]=%08h",dut.ram.mem[128]); $fdisplay(state_file,"ram[00000204]=%08h",dut.ram.mem[129]); $fdisplay(state_file,"ram[00000208]=%08h",dut.ram.mem[130]); $fdisplay(state_file,"ram[000003fc]=%08h",dut.ram.mem[255]);
        $fdisplay(perf_file,"cycles=%0d",cycles); $fdisplay(perf_file,"retired_instructions=%0d",retired); $fdisplay(perf_file,"cpi_x1000=%0d",(1000*cycles)/retired);
        $fclose(trace_file);$fclose(state_file);$fclose(perf_file); $display("GCC EVIDENCE PASS");$finish;
    end
    initial begin #50000; $fatal(1,"GCC evidence timeout"); end
endmodule
