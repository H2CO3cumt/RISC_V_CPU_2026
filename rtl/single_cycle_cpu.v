module single_cycle_cpu #(
    parameter IMEM_DEPTH = 256,
    parameter DMEM_DEPTH = 256,
    parameter IMEM_INIT_FILE = ""
) (
    input wire clk,
    input wire reset,
    // Candidate reference-model commit trace.  These are observation-only
    // signals and do not participate in instruction execution.
    output wire        trace_valid,
    output wire [31:0] trace_pc,
    output wire [31:0] trace_instruction,
    output wire        trace_rd_we,
    output wire [4:0]  trace_rd_addr,
    output wire [31:0] trace_rd_data,
    output wire        trace_mem_we,
    output wire [31:0] trace_mem_addr,
    output wire [31:0] trace_mem_data,
    output wire [3:0]  trace_mem_wstrb,
    output wire        trace_error,
    output wire        event_illegal,
    output wire        event_misaligned,
    output wire        event_bus_error,
    output wire        d_req_valid,
input  wire        d_req_ready,
output wire [31:0] d_req_addr,
output wire        d_req_write,
output wire [31:0] d_req_wdata,
output wire [3:0]  d_req_wstrb,

input  wire        d_rsp_valid,
output wire        d_rsp_ready,
input  wire [31:0] d_rsp_rdata,
input  wire        d_rsp_error,
output wire        i_req_valid,
input  wire        i_req_ready,
output wire [31:0] i_req_addr,

input  wire        i_rsp_valid,
output wire        i_rsp_ready,
input  wire [31:0] i_rsp_data,
input  wire        i_rsp_error
);
reg [31:0] pc;//当前取值地址
localparam MEM_RUN=2'd0;//当前没有等待访存
localparam MEM_REQ=2'd1;//正在持续发送请求，等待d_req_ready;
localparam MEM_RSP=2'd2;//请求已被接受，等待d_rsp_valid;
reg [1:0]mem_state;
//取指事务:先等待SoC接受PC,再等待SoC返回该PC对应的指令
localparam IF_REQ=2'd0;
localparam IF_RSP=2'd1;
localparam IF_DONE=2'd2;
reg [1:0] if_state;
reg [31:0] instruction_reg;
reg instruction_error;
wire [31:0] pc_next;//下一个取指地址
wire [31:0] pc_plus4;//顺序执行地址
//指令由SoC的取指响应保存；EXEC/MCM阶段始终使用这份稳定副本
wire [31:0] instruction;
assign instruction=instruction_reg;
wire [4:0] rs1_addr;
wire [4:0] rs2_addr;
wire [4:0]rd_addr;
wire [2:0] funct3;
assign rs1_addr = instruction[19:15];
assign rs2_addr = instruction[24:20];
assign rd_addr = instruction[11:7];
assign funct3 = instruction[14:12];
assign pc_plus4=pc+32'd4;
//IF_REQ持续请求当前PC:IF_RSP持续准备接收返回指令
assign i_req_valid=(if_state==IF_REQ);
assign i_req_addr=pc;
assign i_rsp_ready=(if_state==IF_RSP);
wire [31:0] imm;//立即数
wire reg_write;
wire alu_src_a;
wire alu_src_b;
wire [3:0]alu_ctrl;
wire mem_read;
wire mem_write;
wire [1:0]result_src;
wire branch;
wire jump;
wire jalr;
wire illegal;
    imm_gen u_imm_gen(
        .instruction(instruction),
        .imm(imm)
    );
    decoder u_decoder(
        .instruction(instruction),
        .reg_write(reg_write),
        .alu_src_a(alu_src_a),
        .alu_src_b(alu_src_b),
        .alu_ctrl(alu_ctrl),
        .mem_read(mem_read),
        .mem_write(mem_write),
        .result_src(result_src),
        .branch(branch),
        .jump(jump),
        .jalr(jalr),
        .illegal(illegal)
    );//指令产生控制信号和立即数
wire [31:0] rs1_data;
wire [31:0] rs2_data;
wire [31:0] wb_data;
wire reg_write_effective;
    regfile u_regfile(
        .clk(clk),
        .rd_we(reg_write_effective),
        .rd_addr(rd_addr),
        .rd_data(wb_data),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),//当前指令读取的寄存器
        .rs2_data(rs2_data)//当前指令读取的寄存器
    );
wire [31:0] alu_a;
wire [31:0] alu_b;
wire [31:0] alu_result;
assign alu_a= alu_src_a ? pc : rs1_data;
assign alu_b= alu_src_b ? imm : rs2_data;
alu u_alu(
    .a(alu_a),
    .b(alu_b),
    .alu_ctrl(alu_ctrl),
    .result(alu_result)/*ADDI/ADD/SUB 的待写回结果；
LW/SW 的字节地址；
BEQ/JAL 的跳转目标 PC+imm。*/
);
wire [31:0] load_data;
wire [31:0] store_wdata;
wire [3:0] store_wstrb;
wire misaligned;
//相应握手代表本次访存真正结束；等待周期不能提交或者产生Store记录
wire mem_rsp_fire;
wire load_complete;
wire store_complete;
wire nonmem_retire;
wire retire_valid;
assign mem_rsp_fire=(mem_state==MEM_RSP) && d_rsp_valid && d_rsp_ready;
load_store_unit u_load_store_unit(
    .addr_low(alu_result[1:0]),
    .funct3(funct3),
    //SoC返回对齐的32-bit word；load_store_unit再按LB/LH/LW选lane
    .mem_rdata(d_rsp_rdata),
    .store_data(rs2_data),
    .is_load(mem_read),
    .is_store(mem_write),
    .load_data(load_data),
    .store_wdata(store_wdata),
    .store_wstrb(store_wstrb),
    .misaligned(misaligned)
);
//访问出错时，PC会继续，但禁止寄存器或内存副作用
assign load_complete=mem_rsp_fire && mem_read && !d_rsp_error;
assign store_complete=mem_rsp_fire && mem_write && !d_rsp_error;
//普通指令在MEM_RUN当拍完成，合法LOAD/Store必须等响应握手
wire mem_access;
//只有取指完成后的普通指令才能退休；取指等待周期不算执行
assign nonmem_retire=(mem_state==MEM_RUN) && !mem_access && (if_state==IF_DONE);
assign retire_valid= nonmem_retire|| mem_rsp_fire;
assign mem_access=(mem_read||mem_write) && !misaligned;
//只有进入MEM_REQ才向SoC声明一笔有效访存请求。
//在ready=0期间PC不变，因此以下请求字段也保持不变
assign d_req_valid=(mem_state==MEM_REQ);
assign d_req_addr=alu_result;
assign d_req_write=mem_write;
assign d_req_wdata=store_wdata;
assign d_req_wstrb=store_wstrb;
//请求已被接受后，Core在MEM_RSP等待并接受唯一一次响应
assign d_rsp_ready=(mem_state==MEM_RSP);
//ALU/JAL等非访存指令在MEM_RUN写回;Load只能使用完成响应的数据写回
assign reg_write_effective=
    ((mem_state==MEM_RUN)&& reg_write && !mem_read && (if_state==IF_DONE))||
    load_complete;
assign wb_data = 
        (result_src==2'b00)?alu_result:
        (result_src==2'b01)?load_data:
        (result_src==2'b10)?pc_plus4:
                            imm;
/*00：ADDI / ADD / SUB 的 ALU 结果
01：LW 从 DMEM 得到、经 load_store_unit 处理的数据
10：JAL 要写入 rd 的返回地址 PC+4
11：LUI 的 imm*/
wire branch_taken;
branch_unit u_branch_unit(
    .a(rs1_data),
    .b(rs2_data),
    .funct3(funct3),
    .taken(branch_taken)
);
assign pc_next=
        jump? (jalr?alu_result & 32'hFFFF_FFFE: alu_result): //区别JAL和JALR
        (branch && branch_taken)? alu_result:
                    pc_plus4;
always@(posedge clk)begin
        if(reset)begin
            if_state<=IF_REQ;
            instruction_reg<=32'b0;
            instruction_error<=1'b0;
        end
        else begin
            case(if_state)
            //保持同一个PC发取指请求，知道SoC明确接收
            IF_REQ:if(i_req_ready)
                    if_state<=IF_RSP;
            //请求已接收；只有拿到响应后才允许后续译码和执行
            IF_RSP:if(i_rsp_valid)begin
                instruction_reg<=i_rsp_error?32'b0:i_rsp_data;
                instruction_error<=i_rsp_error;
                if_state<=IF_DONE;
            end
            IF_DONE:if(retire_valid)
                    if_state<=IF_REQ;
            default:begin
                if_state<=IF_REQ;
                instruction_reg<=32'b0;
            end
            endcase//总的意思就是先拿到并保存一条指令，才允许执行；执行结束后才取下一条
        end
end
always@(posedge clk)begin
    if(reset) begin
        pc<=32'd0;
        mem_state<=MEM_RUN;
    end
    else begin
        case(mem_state)
        //指令尚未从SoC返回时，不能把旧的instruction_reg当作新的指令执行
            MEM_RUN:if(if_state!=IF_DONE)begin
                pc<=pc;
                mem_state<=MEM_RUN;
            end
            else if(mem_access)begin
                pc<=pc;
                mem_state<=MEM_REQ;
            end
            else begin
                pc<=pc_next;
                mem_state<=MEM_RUN;
            end
        //请求未被SoC接受前，PC保持，后续会持续保持同一笔请求字段
            MEM_REQ:begin
                pc<=pc;
                if(d_req_ready)
                    mem_state<=MEM_RSP;
                else mem_state<=MEM_REQ;
            end
        //请求已经接受；保持PC，等待SoC返回完成响应后才让该访存指令完成。
            MEM_RSP:if(d_rsp_valid)begin
                pc<=pc_next;
                mem_state<=MEM_RUN;
            end
            else begin
                pc<=pc;
                mem_state<=MEM_RSP;
            end
            default:begin
                pc<=32'd0;
                mem_state<=MEM_RUN;
            end
        endcase
    end
end
// A non-reset single-cycle CPU retires exactly the instruction currently at
// pc on every clock edge.  Fields without an architectural side effect are
// driven to zero so traces can be compared mechanically.
assign trace_valid       = !reset && retire_valid;
assign trace_error       = trace_valid &&
                           (instruction_error || illegal || misaligned ||
                            (mem_rsp_fire && d_rsp_error));
assign event_illegal     = trace_valid && !instruction_error && illegal;
assign event_misaligned  = trace_valid && misaligned;
assign event_bus_error   = (i_rsp_valid && i_rsp_ready && i_rsp_error) ||
                           (mem_rsp_fire && d_rsp_error);
assign trace_pc          = trace_valid ? pc : 32'b0;
assign trace_instruction = trace_valid ? instruction : 32'b0;
assign trace_rd_we       = trace_valid && reg_write_effective && (rd_addr != 5'd0);
assign trace_rd_addr     = trace_rd_we ? rd_addr : 5'b0;
assign trace_rd_data     = trace_rd_we ? wb_data : 32'b0;
assign trace_mem_we      = trace_valid && store_complete;
assign trace_mem_addr    = trace_mem_we ? alu_result : 32'b0;
assign trace_mem_data    = trace_mem_we ? store_wdata : 32'b0;
assign trace_mem_wstrb   = trace_mem_we ? store_wstrb : 4'b0;
endmodule
