`timescale 1ns/1ps

module tb_soc_fpga_dmem;
    reg clk = 1'b0;
    reg reset = 1'b1;
    reg req_valid = 1'b0;
    reg [31:0] req_addr = 32'b0;
    reg req_write = 1'b0;
    reg [31:0] req_wdata = 32'b0;
    reg [3:0] req_wstrb = 4'b0;
    reg rsp_ready = 1'b1;
    wire req_ready;
    wire rsp_valid;
    wire [31:0] rsp_rdata;
    wire rsp_error;
    integer failures = 0;

    soc_fpga_dmem #(.DEPTH(256)) dut (
        .clk(clk),
        .reset(reset),
        .req_valid(req_valid),
        .req_ready(req_ready),
        .req_addr(req_addr),
        .req_write(req_write),
        .req_wdata(req_wdata),
        .req_wstrb(req_wstrb),
        .rsp_valid(rsp_valid),
        .rsp_ready(rsp_ready),
        .rsp_rdata(rsp_rdata),
        .rsp_error(rsp_error)
    );

    always #5 clk = ~clk;

    task transact;
        input [31:0] address;
        input write_enable;
        input [31:0] write_data;
        input [3:0] write_strobe;
        input [31:0] expected_read_data;
        input expected_error;
        begin
            @(negedge clk);
            req_addr = address;
            req_write = write_enable;
            req_wdata = write_data;
            req_wstrb = write_strobe;
            req_valid = 1'b1;
            wait (req_ready);
            @(posedge clk);
            #1;
            req_valid = 1'b0;
            req_write = 1'b0;
            req_wstrb = 4'b0;
            if (!rsp_valid || rsp_error !== expected_error) begin
                $display("TEST DMEM response FAIL addr=%h error=%b", address, rsp_error);
                failures = failures + 1;
            end
            else if (!write_enable && !expected_error && rsp_rdata !== expected_read_data) begin
                $display("TEST DMEM read FAIL addr=%h got=%h expected=%h",
                         address, rsp_rdata, expected_read_data);
                failures = failures + 1;
            end
            else begin
                $display("TEST DMEM transaction PASS addr=%h", address);
            end
            @(posedge clk);
            #1;
        end
    endtask

    initial begin
        repeat (2) @(posedge clk);
        reset = 1'b0;

        // 初始化镜像中的 "Hell"，随后验证整字写回。
        transact(32'd84, 1'b0, 32'b0, 4'b0, 32'h6c6c_6548, 1'b0);
        transact(32'd84, 1'b1, 32'h1234_5678, 4'b1111, 32'b0, 1'b0);
        transact(32'd84, 1'b0, 32'b0, 4'b0, 32'h1234_5678, 1'b0);

        // 第一次部分写入必须保留初始化镜像中未选中的字节。
        transact(32'd88, 1'b1, 32'h0000_aa00, 4'b0010, 32'b0, 1'b0);
        transact(32'd88, 1'b0, 32'b0, 4'b0, 32'h4952_aa6f, 1'b0);

        transact(32'd1024, 1'b0, 32'b0, 4'b0, 32'b0, 1'b1);

        if (failures == 0) begin
            $display("ALL SOC FPGA DMEM TEST PASS");
        end
        else begin
            $fatal(1, "SOC FPGA DMEM %0d TESTS FAIL", failures);
        end
        $finish;
    end

    initial begin
        #100000;
        $fatal(1, "SOC FPGA DMEM TIMEOUT");
    end
endmodule
