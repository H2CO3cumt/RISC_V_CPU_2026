// APP 窗口三目标汇合：性能计数器（0x0）/ 逻辑分析仪（0x1）/ 提交级 trace（0x2）。
//
// 为什么新写一个模块，而不是给 application_mmio_mux.v 加第三组端口：
//   那个模块是 G11 逻辑分析仪 100/100 板级验收与既有 SoC 单测正在使用的一环。
//   给它加端口意味着所有既有板级顶层都要跟着改接线，等于为了新功能去动一条
//   已经封存的路径。这里改成**外面再包一层**：既有两个子窗口原样交给原来的
//   application_mmio_mux（一行不改），只有 `req_addr[11:8]==4'h2` 的这一段被
//   本层截走送给 core_trace_mmio。因此：
//     · application_mmio_mux.v、perf_mmio.v、logic_analyzer_mmio.v **一个字节都没动**；
//     · 既有 0x0/0x1 两条路径的时序、优先级、错误响应与包一层之前逐位相同；
//     · 0x3~0xF 仍然由内层报"未映射"，行为不变。
//
// 子窗口划分依据 docs/interfaces.md §3.2「新增外设只允许新增窗口或复用 APP 窗口
// 内部的子区间，不得改动上表已有窗口」。
module application_mmio_mux3(
 input wire clk,input wire reset,

 // ---- Core 侧：与 application_mmio_mux 完全相同的端口形状 ----
 input wire req_valid,output wire req_ready,input wire [31:0] req_addr,
 input wire req_write,input wire [31:0] req_wdata,input wire [3:0] req_wstrb,
 output wire rsp_valid,input wire rsp_ready,output wire [31:0] rsp_rdata,output wire rsp_error,

 // ---- 性能计数器子窗口 0x1000_2000..0x1000_20FF ----
 output wire perf_req_valid,input wire perf_req_ready,output wire [31:0] perf_req_addr,
 output wire perf_req_write,output wire [31:0] perf_req_wdata,output wire [3:0] perf_req_wstrb,
 input wire perf_rsp_valid,output wire perf_rsp_ready,input wire [31:0] perf_rsp_rdata,input wire perf_rsp_error,

 // ---- 逻辑分析仪子窗口 0x1000_2100..0x1000_21FF ----
 output wire la_req_valid,input wire la_req_ready,output wire [31:0] la_req_addr,
 output wire la_req_write,output wire [31:0] la_req_wdata,output wire [3:0] la_req_wstrb,
 input wire la_rsp_valid,output wire la_rsp_ready,input wire [31:0] la_rsp_rdata,input wire la_rsp_error,

 // ---- 提交级 trace 子窗口 0x1000_2200..0x1000_22FF ----
 output wire tr_req_valid,input wire tr_req_ready,output wire [31:0] tr_req_addr,
 output wire tr_req_write,output wire [31:0] tr_req_wdata,output wire [3:0] tr_req_wstrb,
 input wire tr_rsp_valid,output wire tr_rsp_ready,input wire [31:0] tr_rsp_rdata,input wire tr_rsp_error
);
 // 子窗口选择只由地址高位决定，与请求是否被接受无关——与既有两目标的写法一致。
 wire tr_sel = (req_addr[11:8] == 4'h2);

 // trace 子窗口的请求**不再送给内层**，内层因此永远看不到 0x2 段，
 // 它对 0x0/0x1/其它 的行为与包一层之前逐位相同。
 wire inner_req_valid = req_valid && !tr_sel;
 wire inner_req_ready, inner_rsp_valid;
 wire [31:0] inner_rsp_rdata;
 wire        inner_rsp_error;

 assign req_ready    = tr_sel ? tr_req_ready : inner_req_ready;
 assign tr_req_valid = req_valid && tr_sel;
 assign tr_req_addr  = {24'b0, req_addr[7:0]};
 assign tr_req_write = req_write;
 assign tr_req_wdata = req_wdata;
 assign tr_req_wstrb = req_wstrb;
 assign tr_rsp_ready = rsp_ready && tr_rsp_valid;

 // 同一时刻只可能有一个目标在回响应：trace 请求时内层收不到请求，反之亦然。
 assign rsp_valid = tr_rsp_valid || inner_rsp_valid;
 assign rsp_rdata = tr_rsp_valid ? tr_rsp_rdata : inner_rsp_rdata;
 assign rsp_error = tr_rsp_valid ? tr_rsp_error : inner_rsp_error;

 application_mmio_mux inner(
  .clk(clk),.reset(reset),
  .req_valid(inner_req_valid),.req_ready(inner_req_ready),.req_addr(req_addr),
  .req_write(req_write),.req_wdata(req_wdata),.req_wstrb(req_wstrb),
  .rsp_valid(inner_rsp_valid),.rsp_ready(rsp_ready && !tr_rsp_valid),
  .rsp_rdata(inner_rsp_rdata),.rsp_error(inner_rsp_error),
  .perf_req_valid(perf_req_valid),.perf_req_ready(perf_req_ready),.perf_req_addr(perf_req_addr),
  .perf_req_write(perf_req_write),.perf_req_wdata(perf_req_wdata),.perf_req_wstrb(perf_req_wstrb),
  .perf_rsp_valid(perf_rsp_valid),.perf_rsp_ready(perf_rsp_ready),.perf_rsp_rdata(perf_rsp_rdata),
  .perf_rsp_error(perf_rsp_error),
  .la_req_valid(la_req_valid),.la_req_ready(la_req_ready),.la_req_addr(la_req_addr),
  .la_req_write(la_req_write),.la_req_wdata(la_req_wdata),.la_req_wstrb(la_req_wstrb),
  .la_rsp_valid(la_rsp_valid),.la_rsp_ready(la_rsp_ready),.la_rsp_rdata(la_rsp_rdata),
  .la_rsp_error(la_rsp_error)
 );
endmodule
