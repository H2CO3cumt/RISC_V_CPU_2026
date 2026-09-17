module gpio_mmio (
    input  wire        clk,
    input  wire        reset,

    // 来自互连的请求
    input  wire        gpio_req_valid,
    output wire        gpio_req_ready,
    input  wire [31:0] gpio_req_addr,
    input  wire        gpio_req_write,
    input  wire [31:0] gpio_req_wdata,
    input  wire [3:0]  gpio_req_wstrb,

    // 返回互连的响应
    output wire        gpio_rsp_valid,
    input  wire        gpio_rsp_ready,
    output wire [31:0] gpio_rsp_rdata,
    output wire        gpio_rsp_error,

    // 到 SoC 顶层／之后的 board wrapper
    output wire [31:0] gpio_out
);
localparam IDLE=1'b0;
localparam RESP=1'b1;
reg        resp_pending;
reg [31:0] gpio_out_reg;
reg [31:0] rsp_rdata_reg;
reg        rsp_error_reg;
reg wrapper_cstate;
reg wrapper_nstate;
assign gpio_out=gpio_out_reg;
assign gpio_rsp_rdata=rsp_rdata_reg;
assign gpio_rsp_error=rsp_error_reg;
always@(posedge clk) begin
    if(reset) 
        wrapper_cstate<=IDLE;
    else wrapper_cstate<=wrapper_nstate;
end
always@(*)begin
    wrapper_nstate=IDLE;
    case(wrapper_cstate)
    IDLE:if(gpio_req_valid && gpio_req_ready)
            wrapper_nstate=RESP;
         else 
            wrapper_nstate=IDLE;
    RESP:if(gpio_rsp_valid && gpio_rsp_ready)
            wrapper_nstate=IDLE;
         else 
            wrapper_nstate=RESP;
    default:wrapper_nstate=IDLE;
    endcase
end
always@(posedge clk)begin
    if(reset) begin
    gpio_out_reg<=32'd0;
    rsp_rdata_reg<=32'd0;
    rsp_error_reg<=0;
    end
    else begin
        case(wrapper_cstate)
        IDLE: 
            if(gpio_req_valid && gpio_req_ready)begin
                if(gpio_req_addr[7:2]!=0)begin
                rsp_error_reg<=1;
                rsp_rdata_reg<=32'd0;
                end
              else   if(gpio_req_write) begin
                rsp_error_reg<=0;
                rsp_rdata_reg<=32'd0;
                    if(gpio_req_wstrb[0])
                        gpio_out_reg[7:0]<=gpio_req_wdata[7:0];
                    if(gpio_req_wstrb[1])
                        gpio_out_reg[15:8]<=gpio_req_wdata[15:8];
                    if(gpio_req_wstrb[2])
                        gpio_out_reg[23:16]<=gpio_req_wdata[23:16];
                    if(gpio_req_wstrb[3])
                        gpio_out_reg[31:24]<=gpio_req_wdata[31:24];
                end
                else  begin   //合法读
                    rsp_error_reg<=0;
                    rsp_rdata_reg<=gpio_out_reg;
                    gpio_out_reg<=gpio_out_reg;
                end
        end
        RESP:begin
        end
        endcase
    end
end
assign gpio_req_ready=(wrapper_cstate==IDLE);
assign gpio_rsp_valid=(wrapper_cstate==RESP);
endmodule