// 提交级 trace 的 MMIO 从端口（Core 外部应用外设）。
//
// 位置：APP 窗口的第三个子区间 `0x1000_2200 ~ 0x1000_22FF`
//（perf 用 `0x1000_2000..0x1000_20FF`、逻辑分析仪用 `0x1000_2100..0x1000_21FF`，
//  见 docs/interfaces.md §3.2）。新增子区间不改动任何既有窗口，也不改 Core，
//  沿用"新增外设只允许新增窗口或复用 APP 窗口内部子区间"的既有约定。
//
// 为什么单独做一个模块，而不是往 logic_analyzer_mmio.v 里塞：
//   那个模块已经带着 G11 的 100/100 板级验收与既有单测，改它等于为了新功能
//   去动一条已经封存的路径。本项目纪律是"已经 Regression PASS 的模块不得无理由
//   修改"，所以这里另起一个从设备，只让 application_mmio_mux 多一个目标。
//
// 寄存器表（窗口内 byte offset；16 位寄存器按 wstrb 低位/次位分字节写，
// 其余寄存器以 wstrb[0] 作为"这一笔写的是本寄存器"的门控，零 strobe 无副作用）：
//   0x00 CTRL      W  [0]=arm [1]=stop [2]=clear   三个自清脉冲
//   0x04 STATUS    R  [0]=armed [1]=recording [2]=done [3]=overflow
//   0x08 COUNT     R  已记录条数（一条 = 一条退休指令）
//   0x0C MARKCOUNT R  已打点个数
//   0x10 RD_INDEX  W/R 记录读指针
//   0x14 RD_W0     R  记录 [31:0]    pc[11:0] / instruction[19:0]
//   0x18 RD_W1     R  记录 [63:32]   instruction[31:20] / rd_we / rd_addr / rd_data 低 15 位
//   0x1C RD_W2     R  记录 [95:64]
//   0x20 RD_W3     R  记录 [131:96]（高 4 位为零）
//   0x24 MARK_INDEX W/R 打点表读指针
//   0x28 MARK_RD   R  {8'b0, index[15:0], value[7:0]}
//   0x2C MARK_WR   W  [7:0] = 标记值，写这一笔等于打一个点（自清脉冲）
//   0x30 RD_W4     R  记录 [131:128]（只有低 4 位有效）
//
// 为什么要第 5 个字：记录 132 位装不进 4 个 32 位字。第一版把 RD_W3 写成
// `{28'b0, rd_record[131:96]}`，那会把 128..131 这 4 位**静默截掉**——
// 页面上表现为"error 位永远是 0、mem_data 最高 4 位永远丢失"，属于最难查的
// 一类：看着有数据，其实少了几位。宁可多读一个字，也不做有损截断。
//
// 约定的使用顺序（固件照此实现，上位机照此判读）：
//   clear → 写 CTRL.arm → 做被测的工作（期间可写 MARK_WR 打点）
//   → 写 CTRL.stop → 读 STATUS/COUNT → 按 RD_INDEX 逐条读 4 个字导出
module core_trace_mmio #(
 parameter DEPTH = 4096,
 parameter MARKS = 256,
 parameter AW    = 12,
 parameter MW    = 8
)(
 input wire clk,
 input wire reset,

 // ---- MMIO 从端口：与其它外设完全一致的通用事务语义 ----
 input wire        req_valid,
 output wire       req_ready,
 input wire [31:0] req_addr,
 input wire        req_write,
 input wire [31:0] req_wdata,
 input wire [3:0]  req_wstrb,
 output reg        rsp_valid,
 input wire        rsp_ready,
 output reg  [31:0] rsp_rdata,
 output reg        rsp_error,

 // ---- 提交级 trace：取自 Core 已有的对外观测输出，只做观察 ----
 input wire        trace_valid,
 input wire [31:0] trace_pc,
 input wire [31:0] trace_instruction,
 input wire        trace_rd_we,
 input wire [4:0]  trace_rd_addr,
 input wire [31:0] trace_rd_data,
 input wire        trace_mem_we,
 input wire [31:0] trace_mem_addr,
 input wire [31:0] trace_mem_data,
 input wire [3:0]  trace_mem_wstrb,
 input wire        trace_error
);
 reg arm, stop, clear, mark;
 reg [7:0]  mark_value;
 reg [15:0] rd_index;
 reg [MW-1:0] mark_index;

 wire [131:0] rd_record;
 wire [23:0]  rd_mark;
 wire armed, recording, done, overflow;
 wire [15:0] count, mark_count;

 // 实例名不能叫 buf——`buf` 是 Verilog 内建原语（缓冲门），会被当成门级实例解析。
 trace_buffer #(.DEPTH(DEPTH), .MARKS(MARKS), .AW(AW), .MW(MW)) u_buf(
  .clk(clk), .reset(reset),
  .trace_valid(trace_valid), .trace_pc(trace_pc), .trace_instruction(trace_instruction),
  .trace_rd_we(trace_rd_we), .trace_rd_addr(trace_rd_addr), .trace_rd_data(trace_rd_data),
  .trace_mem_we(trace_mem_we), .trace_mem_addr(trace_mem_addr), .trace_mem_data(trace_mem_data),
  .trace_mem_wstrb(trace_mem_wstrb), .trace_error(trace_error),
  .arm(arm), .stop(stop), .clear(clear), .mark(mark), .mark_value(mark_value),
  .rd_index(rd_index), .mark_index(mark_index),
  .rd_record(rd_record), .rd_mark(rd_mark),
  .armed(armed), .recording(recording), .done(done), .overflow(overflow),
  .count(count), .mark_count(mark_count)
 );

 // 单 outstanding：上一笔响应没被取走前不接受新请求（与 logic_analyzer_mmio 同构）
 assign req_ready = !rsp_valid;
 wire valid_offset = (req_addr[1:0] == 2'b00) && (req_addr[7:2] <= 6'd12);

 always @(posedge clk) begin
  if(reset) begin
   rsp_valid<=1'b0; rsp_rdata<=32'd0; rsp_error<=1'b0;
   arm<=1'b0; stop<=1'b0; clear<=1'b0; mark<=1'b0; mark_value<=8'd0;
   rd_index<=16'd0; mark_index<={MW{1'b0}};
  end else begin
   // 三个控制位与打点都是**单拍脉冲**：默认清零，只在请求被接受的那一拍置起。
   // 这样"读寄存器"绝不会意外触发一次 Arm 或一次打点。
   arm<=1'b0; stop<=1'b0; clear<=1'b0; mark<=1'b0;

   if(rsp_valid && rsp_ready) rsp_valid<=1'b0;

   if(req_valid && req_ready) begin
    rsp_valid<=1'b1;
    rsp_error<=!valid_offset;
    rsp_rdata<=32'd0;
    if(valid_offset && !req_write) begin
     case(req_addr[7:2])
      6'd1:  rsp_rdata <= {28'b0, overflow, done, recording, armed};
      6'd2:  rsp_rdata <= {16'b0, count};
      6'd3:  rsp_rdata <= {16'b0, mark_count};
      6'd4:  rsp_rdata <= {16'b0, rd_index};
      6'd5:  rsp_rdata <= rd_record[31:0];
      6'd6:  rsp_rdata <= rd_record[63:32];
      6'd7:  rsp_rdata <= rd_record[95:64];
      6'd8:  rsp_rdata <= rd_record[127:96];
      6'd9:  rsp_rdata <= {{(32-MW){1'b0}}, mark_index};
      6'd10: rsp_rdata <= {8'b0, rd_mark};
      6'd12: rsp_rdata <= {28'b0, rd_record[131:128]};
      default: rsp_rdata <= 32'd0;
     endcase
    end
    if(valid_offset && req_write) begin
     case(req_addr[7:2])
      6'd0: begin
       // 三根自清控制线；同一笔写里同时置多个位按 RTL 优先级生效（clear > arm > stop
       // 由 trace_buffer 内部顺序决定），固件不这么用，这里只做门控不做仲裁。
       if(req_wstrb[0]) begin
        arm   <= req_wdata[0];
        stop  <= req_wdata[1];
        clear <= req_wdata[2];
       end
      end
      6'd4: begin
       if(req_wstrb[0]) rd_index[7:0]  <= req_wdata[7:0];
       if(req_wstrb[1]) rd_index[15:8] <= req_wdata[15:8];
      end
      6'd9: begin
       // 打点表指针只有 MW 位，写高位字节没有意义，只认低字节
       if(req_wstrb[0]) mark_index <= req_wdata[MW-1:0];
      end
      6'd11: begin
       // 写这一笔 = 打一个点：值取 wdata[7:0]，与 mark_index 无关（打点总是追加）
       if(req_wstrb[0]) begin
        mark <= 1'b1;
        mark_value <= req_wdata[7:0];
       end
      end
      default: begin end
     endcase
    end
   end
  end
 end
endmodule
