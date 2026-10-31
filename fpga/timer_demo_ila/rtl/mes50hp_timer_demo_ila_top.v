// M-24 / N2 板级 ILA 诊断位流的顶层包装。
//
// 【为什么只有两行】
//   和 `fpga/coremark_ila` 用的是同一个套路：把探针与 DebugCore 放在**被复用顶层的
//   `ifdef 里**，再由这里的包装文件把宏定义打开。好处是：
//     - 同一个 `mes50hp_timer_demo_top.v` 既是已交付 N1 位流的顶层，也是本诊断位流的顶层，
//       不存在"两份会漂移的顶层"；
//     - 不定义宏时（即交付的 N1 构建）该文件完全看不到，**N1 位流不受任何影响**。
//   注意：`compile -top_module` 要写**被 include 进来的模块名**（mes50hp_timer_demo_top），
//   不是这个包装文件名 —— coremark_ila 的配方也是这么做的。
`define PDS_TIMER_DEMO_ILA
`include "../../timer_demo/rtl/mes50hp_timer_demo_top.v"
