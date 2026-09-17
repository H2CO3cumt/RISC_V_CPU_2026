module load_store_unit (
    input  wire [1:0]  addr_low,
    input  wire [2:0]  funct3,
    input  wire [31:0] mem_rdata,
    input  wire [31:0] store_data,
    input  wire        is_load,
    input  wire        is_store,
    output reg  [31:0] load_data,
    output reg  [31:0] store_wdata,
    output reg  [3:0]  store_wstrb,
    output reg         misaligned
);

always @(*) begin
    load_data   = 32'b0;
    store_wdata = 32'b0;
    store_wstrb = 4'b0000;
    misaligned  = 1'b0;

    if (is_load) begin
        case (funct3)
            3'b000: begin // LB
                case (addr_low)
                    2'b00: load_data = {{24{mem_rdata[7]}},  mem_rdata[7:0]};
                    2'b01: load_data = {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                    2'b10: load_data = {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                    2'b11: load_data = {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (addr_low)
                    2'b00: load_data = {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                    2'b10: load_data = {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                    default: misaligned = 1'b1;
                endcase
            end
            3'b010: begin // LW
                if (addr_low == 2'b00)
                    load_data = mem_rdata;
                else
                    misaligned = 1'b1;
            end
            3'b100: begin // LBU
                case (addr_low)
                    2'b00: load_data = {24'b0, mem_rdata[7:0]};
                    2'b01: load_data = {24'b0, mem_rdata[15:8]};
                    2'b10: load_data = {24'b0, mem_rdata[23:16]};
                    2'b11: load_data = {24'b0, mem_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (addr_low)
                    2'b00: load_data = {16'b0, mem_rdata[15:0]};
                    2'b10: load_data = {16'b0, mem_rdata[31:16]};
                    default: misaligned = 1'b1;
                endcase
            end
            default: begin
                // Keep safe defaults for unsupported Load encodings.
            end
        endcase
    end
    else if (is_store) begin
        case (funct3)
            3'b000: begin // SB
                case (addr_low)
                    2'b00: begin
                        store_wdata = {24'b0, store_data[7:0]};
                        store_wstrb = 4'b0001;
                    end
                    2'b01: begin
                        store_wdata = {16'b0, store_data[7:0], 8'b0};
                        store_wstrb = 4'b0010;
                    end
                    2'b10: begin
                        store_wdata = {8'b0, store_data[7:0], 16'b0};
                        store_wstrb = 4'b0100;
                    end
                    2'b11: begin
                        store_wdata = {store_data[7:0], 24'b0};
                        store_wstrb = 4'b1000;
                    end
                endcase
            end
            3'b001: begin // SH
                case (addr_low)
                    2'b00: begin
                        store_wdata = {16'b0, store_data[15:0]};
                        store_wstrb = 4'b0011;
                    end
                    2'b10: begin
                        store_wdata = {store_data[15:0], 16'b0};
                        store_wstrb = 4'b1100;
                    end
                    default: misaligned = 1'b1;
                endcase
            end
            3'b010: begin // SW
                if (addr_low == 2'b00) begin
                    store_wdata = store_data;
                    store_wstrb = 4'b1111;
                end
                else begin
                    misaligned = 1'b1;
                end
            end
            default: begin
                // Keep safe defaults for unsupported Store encodings.
            end
        endcase
    end
end

endmodule
