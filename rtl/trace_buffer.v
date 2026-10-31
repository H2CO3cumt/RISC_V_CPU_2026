// 提交级 trace 缓冲：把逻辑分析仪的探针从"引脚"伸到"流水线内部"。
//
// 定位与边界（必须保持）：
//   · 数据来源**全部**是 pipeline_cpu 已有的对外观测输出 trace_* 与
//     event_*（docs/interfaces.md §6.1）。本模块只观察、不反馈，Core 的
//     端口、事务语义与 IF/ID/EX/MEM/WB 控制一行都不受影响。
//   · 本模块属于 Core 外部的应用外设，经 APP MMIO 窗口读出面（寄存器语义见
//     rtl/core_trace_mmio.v）。Core 不知道它存在。
//   · 不做任何压缩：本届逻辑分析仪固定 Raw 架构，这里换的只是"每个
//     采样点存多少位"——从 8 位数字线换成一条完整的提交记录。
//
// 注：上面刻意不点名某个具体压缩算法。`scripts\run_scope_audit.ps1` 对**暂不实现**
// 的功能名做的是纯关键词扫描（连"不实现 X"这种说明性注释也会被判违规），
// 而那句说明在这里本来也不需要点名字，所以写成"不做任何压缩"。
// 审计规则本身不因此放宽——暂不实现的功能名仍不应出现在源文件里。
//
// 记录宽度 132 位（字段与 rtl/pipeline_cpu.v 第 17~27 行的端口一一对应）：
//   [131]     trace_error                该条退休记录被抑制了架构副作用
//   [130:99]  trace_mem_data             写存储的数据
//   [98:95]   trace_mem_wstrb            字节写使能
//   [94:83]   trace_mem_addr[11:0]       写存储的字节地址（IMEM/DMEM 各 4 KB，12 位足够）
//   [82]      trace_mem_we               本指令是否写存储
//   [81:50]   trace_rd_data              写回寄存器堆的数据（Load 的数据就在这里）
//   [49:45]   trace_rd_addr              目的寄存器号
//   [44]      trace_rd_we                本指令是否写回
//   [43:12]   trace_instruction          原始指令字（上位机据此做反汇编与依赖分析）
//   [11:0]    trace_pc[11:0]             退休 PC（与 PC 上位机侧 ELF 反汇编对拍，判"镜像同源"）
//
// 为什么要存 instruction 而不是让上位机按 pc 去 ELF 里查：
//   按 pc 查更省 32 位，但那样页面上显示的指令与实际执行的指令之间**没有交叉校验**，
//   一旦位流里的镜像和页面用的 objdump 不是同一份，页面会"看起来很对"却是假的。
//   存下 instruction 之后，上位机可以逐条断言 trace_instruction == objdump[pc]，
//   镜像不同源就当场报错——这是 docs/application_logic_analyzer.md §6.7.5
//   "判据与标注必须同源"的同一条纪律。
module trace_buffer #(
 parameter DEPTH = 4096,   // 记录条数（一条 = 一条退休指令）
 parameter MARKS = 256,    // 软件打点表容量
 parameter AW    = 12,     // log2(DEPTH)
 parameter MW    = 8       // log2(MARKS)
)(
 input wire clk,
 input wire reset,

 // ---- 提交级 trace：Core 已有的对外观测输出，只做观察 ----
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
 input wire        trace_error,

 // ---- 控制面：全部来自 MMIO，arm/stop/clear/mark 是单拍脉冲 ----
 input wire arm,
 input wire stop,
 input wire clear,
 input wire mark,
 input wire [7:0]  mark_value,
 input wire [15:0] rd_index,
 input wire [MW-1:0] mark_index,

 // ---- 数据读出面 ----
 output wire [131:0] rd_record,
 output wire [23:0]  rd_mark,      // {index[15:0], value[7:0]}：低字节是标记值，[23:8] 是记录序号

 // ---- 状态 ----
 output reg armed,
 output reg recording,
 output reg done,
 // overflow 只表示"**容量装不下**"：记录条数到顶之后还有指令退休。
 // 软件主动 stop 完之后 CPU 当然还会继续退休指令，那不算溢出——否则每一次
 // 正常收尾都会把 overflow 置起来，页面上就再也分不清"窗口本来就这么大"和
 // "窗口被撑爆了"（2026-10-21 实测：正常收尾时 status=0x0C，overflow 位是假的）。
 output reg overflow,
 output reg [15:0] count,
 output reg [15:0] mark_count
);
 localparam [15:0] DEPTH16 = DEPTH;

 // 132 位提交记录：拼接顺序必须与上方位段注释逐位一致
 wire [131:0] record = {
   trace_error,
   trace_mem_data,
   trace_mem_wstrb,
   trace_mem_addr[11:0],
   trace_mem_we,
   trace_rd_data,
   trace_rd_addr,
   trace_rd_we,
   trace_instruction,
   trace_pc[11:0]
 };

 reg [131:0] mem[0:DEPTH-1];
 reg [23:0]  marks[0:MARKS-1];
 reg [15:0]  write_ptr;
 reg [MW-1:0] mark_ptr;
 // full 区分两种"收尾"：写满自动收尾（full=1，之后再有退休指令才算溢出）
 // 与软件 stop（full=0，之后再有退休指令是正常的，不算溢出）。
 reg full;

 // 读端口**寄存一拍**：rd_index 是 MMIO 写完就稳定的常数，所以 rd_record 在
 // rd_index 变化后一拍有效并一直保持，固件连读 4 个字（RD_W0..3）期间不会变。
 // 用组合读也能跑，但那样 4096×132 的读出会变成一条长组合路径，85 MHz 下
 // 正是最容易被 PDS 判违例的形状；寄存之后这条路径只剩"BRAM 输出 → FF"。
 reg [131:0] rd_record_q;
 reg [23:0]  rd_mark_q;
 always @(posedge clk) begin
   rd_record_q <= mem[rd_index[AW-1:0]];
   rd_mark_q   <= marks[mark_index];
 end
 assign rd_record = rd_record_q;
 assign rd_mark   = rd_mark_q;

 // 复位/清空**不清 BRAM**：DEPTH=4096 时那条 for 循环会直接撞 PDS 的
 // `Verilog-4092 Loop limit 2000 exceeded`（capture_engine 在 DEPTH=2048 上
 // 已经实测踩过一次，见 docs/application_logic_analyzer.md §6.7.6 的回退记录）。
 // 不清是安全的：软件能读到的范围完全由 count 决定，上电时 mem 里的旧内容
 // 不会被任何导出路径泄漏出去。
 always @(posedge clk) begin
  if(reset || clear) begin
   armed<=1'b0; recording<=1'b0; done<=1'b0; overflow<=1'b0; full<=1'b0;
   count<=16'd0; mark_count<=16'd0; write_ptr<=16'd0; mark_ptr<={MW{1'b0}};
  end else begin
   // arm 优先级最高：它把窗口"清账"，随后由 trace_valid 逐条填充。
   // 同一拍里如果既有 arm 又有 trace_valid，那一条不记录——arm 之后的那条
   // 退休指令才是用户想看的起点，窗口语义因此是"从 arm 后的第一条开始"。
   if(arm) begin
    armed<=1'b1; recording<=1'b1; done<=1'b0; overflow<=1'b0; full<=1'b0;
    count<=16'd0; mark_count<=16'd0; write_ptr<=16'd0; mark_ptr<={MW{1'b0}};
   end else if(stop) begin
    // stop 是软件主动收尾：保留已记录内容，done 置位让固件/上位机知道可以导出。
    // full 保持原值：若之前已经写满，后又来一条指令退休，overflow 仍应置起。
    armed<=1'b0; recording<=1'b0; done<=1'b1;
   end

   // 记录一条退休指令：只在 recording 期间，且每一条 trace_valid 恰好记一条
   if(recording && trace_valid) begin
    mem[write_ptr[AW-1:0]] <= record;
    write_ptr <= write_ptr + 16'd1;
    count     <= count + 16'd1;
    // 写满最后一格就自动收尾；再来的指令只置 overflow，不再覆盖已有记录
    if(write_ptr == DEPTH16 - 16'd1) begin
     recording<=1'b0; armed<=1'b0; done<=1'b1; full<=1'b1;
    end
   end else if(full && trace_valid) begin
    // 只有"窗口是被容量写满而收尾"的，再来指令才叫溢出。
    // 软件 stop 之后的退休指令不计入——那是正常的程序继续执行。
    overflow<=1'b1;
   end

   // 软件打点：索引 = 此刻已经记录的条数，即"下一条记录的位置"。
   // 固件收到一个字符后立刻打点，上位机因此能把字符精确锚到一条指令上。
   if(mark && (mark_count < MARKS)) begin
    // 位段 {index[15:0], value[7:0]}：低字节放字符本身，高位放记录序号。
    // 这样 MMIO 读回来 `rdata[7:0]` 直接就是字符，`rdata[23:8]` 是它锚定的记录位置。
    marks[mark_ptr] <= {count, mark_value};
    mark_ptr <= mark_ptr + {{(MW-1){1'b0}},1'b1};
    mark_count <= mark_count + 16'd1;
   end
  end
 end
endmodule
