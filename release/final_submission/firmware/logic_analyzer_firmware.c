#define UART_TXDATA (*(volatile unsigned int *)0x10000000u)
#define UART_STATUS (*(volatile unsigned int *)0x10000004u)
#define UART_RXDATA (*(volatile unsigned int *)0x10000008u)
#define GPIO_OUT    (*(volatile unsigned int *)0x10001000u)
#define LA_BASE     0x10002100u
#define LA_CONTROL  (*(volatile unsigned int *)(LA_BASE + 0x00u))
#define LA_STATUS   (*(volatile unsigned int *)(LA_BASE + 0x04u))
#define LA_DIV      (*(volatile unsigned int *)(LA_BASE + 0x08u))
#define LA_CH_MASK  (*(volatile unsigned int *)(LA_BASE + 0x0Cu))
#define LA_TR_MASK  (*(volatile unsigned int *)(LA_BASE + 0x10u))
#define LA_TR_VALUE (*(volatile unsigned int *)(LA_BASE + 0x14u))
#define LA_TR_RISE  (*(volatile unsigned int *)(LA_BASE + 0x18u))
#define LA_TR_FALL  (*(volatile unsigned int *)(LA_BASE + 0x1Cu))
#define LA_PRE      (*(volatile unsigned int *)(LA_BASE + 0x20u))
#define LA_POST     (*(volatile unsigned int *)(LA_BASE + 0x24u))
#define LA_TR_INDEX (*(volatile unsigned int *)(LA_BASE + 0x28u))
#define LA_COUNT    (*(volatile unsigned int *)(LA_BASE + 0x2Cu))
#define LA_INDEX    (*(volatile unsigned int *)(LA_BASE + 0x30u))
#define LA_DATA     (*(volatile unsigned int *)(LA_BASE + 0x34u))
#define LA_PAT_CTL  (*(volatile unsigned int *)(LA_BASE + 0x38u))
#define LA_PAT_DIV  (*(volatile unsigned int *)(LA_BASE + 0x3Cu))
#define LA_PAT_DATA (*(volatile unsigned int *)(LA_BASE + 0x40u))
/* 采集源选择（=MMIO 寄存器 18）：0 = J8 外部 8 路物理输入（默认），
   1 = Core 内部观测点（取指/访存握手、停顿、冲刷、提交）。
   之所以做成可写寄存器而不是重综合开关：现场切换采集源必须"不重新综合"。 */
#define LA_SRC      (*(volatile unsigned int *)(LA_BASE + 0x48u))

/* 采集深度必须与 rtl/logic_analyzer_mmio.v 的 DEPTH 参数一致（2048）。 */
#define LA_DEPTH 2048u
/* 一次回包里最多保留并打印多少个"解出来的字节"：镜像模式 25 个字符足够。 */
#define DEC_MAX 64u
/* 镜像抓取命令前缀：字符串由上位机经 CP2102 直接送到 uart0_rx，板级顶层把它镜像到 J8 的
   ch7，因此本次采集只负责"抓"和"报"，板子自己不产生激励。 */
#define LA_MIRROR 0xA7u
/* 0xA8：显式指定采集源的新命令，**16 字节**。
   布局：[0]=0xA8 [1]=mode [2]=data [3]|[4]=pattern_div [5]|[6]=sample_div
         [7]=trigger_type [8]=trigger_mask [9]=trigger_value
         [10]|[11]=pre（16 位小端）[12]|[13]=post（16 位小端）
         [14]=采集源(0=J8 外部,1=Core 内部) [15]=XOR 校验
   为什么比 0xA5 长：0xA5 的 pre/post 各只有 1 字节，而 Core 内部观测点要的是
   "全速采样 + 以一次冲刷为中心的 2048 点窗口"，1 字节根本装不下。
   为什么另开一个命令而不是挤进 0xA5 的空位：13 字节布局已被上位机、解析器与
   板级 100/100 证据锁死，改长度会波及全部既有证据；新命令只在用新功能时出现，
   老路径逐字节不变。 */
#define LA_SRC_CORE 0xA8u
/* 镜像模式固定的解码通道：ch7 = J8-31/32 那一对回环脚。 */
#define LA_MIRROR_CH 7u

/* ---- 提交级 trace 子窗口 0x1000_2200（rtl/core_trace_mmio.v）----------------
   这是"逻辑分析仪的探针伸进流水线"的那一环：窗口里存的不是 8 根数字线，
   而是**每一条退休指令**（pc / 指令字 / 写回目的与数据 / 写存储地址数据字节使能）。
   数据来源是 Core 已有的对外观测输出 trace_*，Core 一行未改。
   寄存器（窗口内 byte offset）：
     0x00 CTRL    写 [0]=arm [1]=stop [2]=clear（三个自清脉冲）
     0x04 STATUS  [0]=armed [1]=recording [2]=done [3]=overflow
     0x08 COUNT / 0x0C MARKCNT / 0x10 RD_IDX / 0x24 M_IDX / 0x28 M_RD / 0x2C M_WR
     0x14..0x20 = 记录第 0..3 个字；0x30 = 第 4 个字（只有低 4 位有效）
   为什么是 5 个字：一条记录 132 位，装不进 4 个 32 位字；少读一个字就是把
   error 位和 mem_data 的高 4 位静默丢掉。 */
#define TR_BASE     0x10002200u
#define TR_CTRL     (*(volatile unsigned int *)(TR_BASE + 0x00u))
#define TR_STATUS   (*(volatile unsigned int *)(TR_BASE + 0x04u))
#define TR_COUNT    (*(volatile unsigned int *)(TR_BASE + 0x08u))
#define TR_MARKCNT  (*(volatile unsigned int *)(TR_BASE + 0x0Cu))
#define TR_RDIDX    (*(volatile unsigned int *)(TR_BASE + 0x10u))
#define TR_W0       (*(volatile unsigned int *)(TR_BASE + 0x14u))
#define TR_W1       (*(volatile unsigned int *)(TR_BASE + 0x18u))
#define TR_W2       (*(volatile unsigned int *)(TR_BASE + 0x1Cu))
#define TR_W3       (*(volatile unsigned int *)(TR_BASE + 0x20u))
#define TR_MIDX     (*(volatile unsigned int *)(TR_BASE + 0x24u))
#define TR_MRD      (*(volatile unsigned int *)(TR_BASE + 0x28u))
#define TR_MWR      (*(volatile unsigned int *)(TR_BASE + 0x2Cu))
#define TR_W4       (*(volatile unsigned int *)(TR_BASE + 0x30u))

/* 记录容量必须与 rtl/core_trace_mmio.v / trace_buffer.v 的 DEPTH 参数一致。
   固件只用它做上界保护：实际导出条数以 TR_COUNT 为准。 */
#define TR_DEPTH 4096u

/* 0xAA：提交级 trace 抓取命令，**4 字节**。
   [0]=0xAA [1]=字符数(1..32) [2]=阶段(0=只记处理过程,1=连串口轮询一起记)
   [3]=XOR([1..2])。
   为什么另开一条命令：0xA5/0xA7（13 字节）与 0xA8（16 字节）的布局都被上位机、
   解析器与板级 100/100 证据锁死，往老报文里挤会波及全部既有证据。 */
#define LA_TRACE_CMD 0xAAu
#define TRACE_BUF_MAX 32u

/* 0xAB：**同一次采集里同时拿"每拍波形"和"每条指令"**，4 字节。
   [0]=0xAB [1]=字符数(1..32) [2]=波形窗口档（0=256,1=512,2=1024,3=2047 个后触发样本）
   [3]=XOR([1..2])。

   为什么值得单开一条命令：tr85 位流里 8 通道分析仪和提交级 trace 本来就在同一个
   设计里（`logic_analyzer_mmio.probe_channels` 接 Core 的握手/停顿/冲刷/提交，
   `core_trace_mmio` 接 trace_*），但过去两者是两条命令、两次运行，于是
   "波形"和"指令流"永远对不到一起。这条命令把两件事塞进**同一次运行**：
     ① 先 arm trace（窗口从下一条退休指令开始），
     ② 再 arm LA（Core 探针源、每拍 1 样本、触发 = 退休脉冲上升沿），
     ③ 跑负载，④ 等 LA 采满，⑤ 再 stop trace（保证波形窗口整段都在 trace 里）。
   这样上位机就能用"波形里的退休脉冲个数"去数 trace 里对应的记录条数，
   再用"数据访问脉冲个数"与"区间内 load+store 条数"对拍，**证明**对齐是对的。
   老的 0xAA/0xA5/0xA7/0xA8 一律不动：它们的布局被既有证据锁死。 */
#define LA_TRACE_WAVE 0xABu
/* Core 探针字里的 bit7 = perf_retire（= Core 的 trace_valid），
   与 fpga/trace85/rtl/mes50hp_trace_top.v 里
   `core_probe_q <= {perf_retire,perf_flush,perf_stall,dr,dv,rv,ir,iv}` 一致。 */
#define LA_PROBE_RETIRE 0x80u

/* 组合命令只在 8 KB 镜像里编。理由是可量化的：4 KB 固件已经用掉 922/1024 个字，
   再加上 0xAB 的处理与打印代码实测**溢出 436 字节**。把镜像容量做成
   `-DRAM_KB=8` + link8k.ld（见 scripts/generate_logic_analyzer_fpga_memory.ps1 的
   -RamKb），就只给 tr85 这档演示位流扩容量，交付工程的默认构建因此**逐字节不变**。 */
#if defined(RAM_KB) && (RAM_KB >= 8)
#define TRACE_WAVE_ENABLED 1
#endif


/* 只在交互式固件里有意义；AUTOSTART 版本没有上位机、也不会走 0xAA 命令，
   不定义它以免 -Wall 报 unused。 */
#if !FINAL_AUTOSTART
static unsigned char trace_buf[TRACE_BUF_MAX];
#endif

static void uart_putc(char c) {
    while ((UART_STATUS & 1u) == 0u) { }
    UART_TXDATA = (unsigned int)(unsigned char)c;
}
#if !FINAL_AUTOSTART
static unsigned int uart_getc(void) {
    while ((UART_STATUS & 4u) == 0u) { }
    return UART_RXDATA & 0xFFu;
}
#endif
static void uart_puts(const char *s) { while (*s) uart_putc(*s++); }
static void uart_hex(unsigned int v) {
    static const char d[] = "0123456789ABCDEF"; int i;
    for (i = 7; i >= 0; --i) uart_putc(d[(v >> (i * 4)) & 0xFu]);
}

/* ---- 流式解码 --------------------------------------------------------------
   为什么必须流式（而不是像以前那样先把整条 Raw 流存进 raw[256]）：
   ① 深度从 256 提到 2048 后，用字节数组也要 2 KB，而数据 RAM 一共只有 4 KB，
      栈会被挤到只剩几百字节；流式一个样本都不留，RAM 占用与深度无关。
   ② 解码本来就是一维单向扫描，不需要随机访问。
   取样点必须在**比特中点**：按位边界取样会把线上真实的 0xA5 解成 0x4A —— 这是
   2026-10-09 在 85 MHz 实板日志（release/evidence/.../uart_00.log 里的 UART:0000004A）
   里定位到的半比特错位，Python 与 PowerShell 侧当时已修，固件侧此前没有修。 */

typedef struct {
    unsigned int bit_samples;   /* 每比特采样点数（上位机按波特率与板级时钟算出） */
    unsigned int half;          /* 半比特偏移，取比特中点 */
    unsigned int in_frame;      /* 是否已认定起始位 */
    unsigned int pos;           /* 距起始位第一个低电平采样点的偏移 */
    unsigned int next_bit;      /* 下一个要取样的比特序号，8 表示停止位 */
    unsigned int value;         /* 正在拼装的字节（LSB 先发） */
    unsigned int prev;          /* 上一拍电平 */
    unsigned int count;         /* 已解出的字节数（可能大于实际存下的个数） */
} uart_stream_t;

static void uart_stream_init(uart_stream_t *st, unsigned int bit_samples) {
    st->bit_samples = (bit_samples == 0u) ? 1u : bit_samples;
    st->half = st->bit_samples / 2u; if (st->half == 0u) st->half = 1u;
    st->in_frame = 0u; st->pos = 0u; st->next_bit = 0u; st->value = 0u;
    st->prev = 1u; st->count = 0u;
}

static void uart_stream_feed(uart_stream_t *st, unsigned int level,
                             unsigned char *out, unsigned int out_max) {
    if (st->in_frame == 0u) {
        /* 只有"上一拍高、本拍低"才认定帧头；其余低电平只是数据位内部的跳变。 */
        if (st->prev == 1u && level == 0u) {
            st->in_frame = 1u; st->pos = 0u; st->next_bit = 0u; st->value = 0u;
        }
    } else {
        st->pos++;
        if (st->next_bit < 8u) {
            if (st->pos == st->bit_samples * (st->next_bit + 1u) + st->half) {
                if (level != 0u) st->value |= (1u << st->next_bit);
                st->next_bit++;
            }
        } else if (st->pos == st->bit_samples * 9u + st->half) {
            /* 停止位为高才算一帧；为低就丢掉这一帧并回到扫描态继续找真帧头，不记假错误。
               成立时**不跳过本帧剩余采样点**：实板采样的边沿有 ±1 个采样点的抖动，
               帧长在 79~81 点之间浮动，固定跳到帧尾会让误差逐帧累积，走到半个比特就开始
               解错字节（2026-10-10 实板实测：12 个字符错 5 个，ascii=HE...MC-V）。
               从停止位取样点之后继续逐点扫，等于每帧都用**自己的起始位**重新对齐，
               误差不再累积；理想波形下与"跳满一帧"逐字节相同。上位机三条解码链同改。 */
            st->in_frame = 0u;
            if (level != 0u) {
                if (st->count < out_max) out[st->count] = (unsigned char)st->value;
                st->count++;
            }
        }
    }
    st->prev = level;
}

/* SPI mode0 的流式解码：ch0=SCLK、ch1=MOSI、ch2=CS（低有效）。 */
typedef struct { unsigned int prev, bits, value, count; } spi_stream_t;

static void spi_stream_init(spi_stream_t *st) {
    st->prev = 0u; st->bits = 0u; st->value = 0u; st->count = 0u;
}
static void spi_stream_feed(spi_stream_t *st, unsigned int v,
                            unsigned char *out, unsigned int out_max) {
    unsigned int active = (v & 4u) == 0u;
    unsigned int rising = st->prev == 0u && (v & 1u) != 0u;
    st->prev = ((v & 1u) != 0u) ? 1u : 0u;
    if (active && rising) {
        st->value = ((st->value << 1u) | ((v >> 1u) & 1u)) & 0xFFu;
        if (++st->bits == 8u) {
            if (st->count < out_max) out[st->count] = (unsigned char)st->value;
            st->count++;
            st->bits = 0u; st->value = 0u;
        }
    } else if (!active) {
        st->bits = 0u; st->value = 0u;
    }
}

static void print_byte_values(const unsigned char *buf, unsigned int n) {
    unsigned int i; for (i = 0u; i < n; ++i) uart_hex(buf[i]);
}
static void print_byte_ascii(const unsigned char *buf, unsigned int n) {
    unsigned int i;
    for (i = 0u; i < n; ++i) {
        unsigned char c = buf[i];
        uart_putc((c >= 0x20u && c < 0x7Fu) ? (char)c : '.');
    }
}

static void capture_and_report(unsigned int mode, unsigned int data,
                               unsigned int pattern_div, unsigned int sample_div,
                               unsigned int trigger_type, unsigned int trigger_mask,
                               unsigned int trigger_value, unsigned int pre,
                               unsigned int post) {
    unsigned int i, n, v, bit_samples, channel;
    static unsigned char dec[DEC_MAX], spi_dec[DEC_MAX];
    uart_stream_t us; spi_stream_t ss;
    /* mode==4 是镜像抓取：data 字段这时表示"每比特采样点数"，pattern_div 无意义。 */
    unsigned int mirror = (mode == 4u) ? 1u : 0u;

    LA_CONTROL = 4u;
    LA_DIV = sample_div; LA_CH_MASK = 0xFFu;
    LA_TR_MASK = trigger_mask; LA_TR_VALUE = trigger_value;
    LA_TR_RISE = trigger_type == 1u ? trigger_mask : 0u;
    LA_TR_FALL = trigger_type == 2u ? trigger_mask : 0u;
    LA_PRE = pre; LA_POST = post;
    if (mirror) {
        /* 激励线全部拉到低电平：被测信号只有 ch7 那一路来自上位机串口线，
           其余 7 路保持确定电平，页面上不会出现"看不懂的跳动"。 */
        LA_PAT_DATA = 0u; LA_PAT_DIV = 0u; LA_PAT_CTL = 4u;
    } else {
        LA_PAT_DATA = data; LA_PAT_DIV = pattern_div;
        LA_PAT_CTL = (mode & 3u) | 4u;
    }
    LA_CONTROL = 1u;
#if !FINAL_AUTOSTART
    /* 交互式固件：Arm 已经生效后才提示上位机发字符串，否则字符串可能比 Arm 早到，
       采集窗口就会从报文中间开始。AUTOSTART 版没有上位机，不打印这一行，
       以免改变 tb_logic_analyzer_soc 依赖的 "LA RAW " 前缀。 */
    uart_puts("LA_ARMED\r\n");
#endif
    while ((LA_STATUS & 4u) == 0u) { }

    n = LA_COUNT; if (n > LA_DEPTH) n = LA_DEPTH;
    bit_samples = mirror ? data : ((pattern_div + 1u) / (sample_div + 1u));
    channel = mirror ? LA_MIRROR_CH : 0u;
    uart_stream_init(&us, bit_samples);
    spi_stream_init(&ss);

    uart_puts("LA RAW count="); uart_hex(n); uart_puts(" trigger="); uart_hex(LA_TR_INDEX); uart_puts("\r\n");
    for (i = 0u; i < n; ++i) {
        LA_INDEX = i; v = LA_DATA & 0xFFu;
        uart_hex(v);
        uart_putc((i + 1u == n) ? '\n' : ' ');
        /* 边读边解：一个样本都不留在 RAM 里，深度再涨也不影响固件内存。 */
        uart_stream_feed(&us, (v >> channel) & 1u, dec, DEC_MAX);
        spi_stream_feed(&ss, v, spi_dec, DEC_MAX);
    }
    if (mirror) {
        /* 镜像模式由固件自己把波形解成字符——这是"板子从波形里读出了什么"的直接证据。 */
        unsigned int stored = (us.count < DEC_MAX) ? us.count : DEC_MAX;
        uart_puts("LA TEXT hex="); print_byte_values(dec, stored);
        uart_puts(" ascii="); print_byte_ascii(dec, stored);
        uart_puts(" bytes="); uart_hex(us.count); uart_puts("\r\n");
    } else {
        uart_puts("UART:"); print_byte_values(dec, (us.count < DEC_MAX) ? us.count : DEC_MAX);
        uart_hex(us.count);
        uart_puts(" SPI:"); uart_hex(ss.count); uart_puts("\r\n");
    }
    uart_puts("LA_DONE\r\n");
}

/* ---- 提交级 trace 抓取 ------------------------------------------------------
   phase=0（默认）：先把整句收进 RAM（不记录），再 Arm，只记录**处理过程**。
       好处是窗口里没有串口轮询噪声，一个字符只占十几条指令，
       页面上"点字符 → 高亮消费它的指令"能一条不漏地对齐。
   phase=1：Arm 放在接收之前，窗口里绝大部分是"等下一个字节"的轮询循环。
       这一版的价值是把"CPU 到底在忙什么"摊开：同一个窗口里能直接数出
       轮询占了多少条指令——和 Core 探针测到的窗口 IPC 是同一类结论。

   两个阶段都靠 MMIO 打点（TR_MWR）把字符锚到记录位置：
   打点记录的是"此刻已记录多少条"，上位机据此把字符贴到时间轴上。 */
#if !FINAL_AUTOSTART
/* 0xAA：只抓指令流。两档阶段都在这里。 */
static void trace_and_report(unsigned int n, unsigned int phase) {
    unsigned int i, c, ntr, nmk, st, x = 0u, ups = 0u;

    if (n == 0u) n = 1u;
    if (n > TRACE_BUF_MAX) n = TRACE_BUF_MAX;

    TR_CTRL = 4u;                       /* clear：清计数与状态，不动 BRAM 内容 */
    if (phase != 0u) {
        TR_CTRL = 1u;                   /* arm：下一拍起记录每一条退休指令 */
        uart_puts("TRACE_ARMED\r\n");
        for (i = 0u; i < n; ++i) {
            c = uart_getc();            /* 这一段在窗口里就是轮询循环 */
            trace_buf[i] = (unsigned char)c;
            TR_MWR = c & 0xFFu;         /* 打点：字符锚在当前记录位置 */
        }
        TR_CTRL = 2u;                   /* stop：收尾，保留已记录内容 */
    } else {
        uart_puts("TRACE_ARMED\r\n");
        for (i = 0u; i < n; ++i) trace_buf[i] = (unsigned char)uart_getc();
        TR_CTRL = 1u;                   /* 只记录下面这个处理循环 */
        for (i = 0u; i < n; ++i) {
            c = trace_buf[i];
            TR_MWR = c & 0xFFu;         /* 打点必须在读取该字符之后、写回之前 */
            if (c >= 0x61u && c <= 0x7Au) { c -= 0x20u; ups++; }
            trace_buf[i] = (unsigned char)c;
            x ^= c;
        }
        TR_CTRL = 2u;
    }

    st = TR_STATUS;
    ntr = TR_COUNT; if (ntr > TR_DEPTH) ntr = TR_DEPTH;
    nmk = TR_MARKCNT;
    /* 回包头部：条数、打点数、状态位，一行说清这一枪抓到了什么。
       over 位如实透传——窗口被写满之后还有指令退休时，页面必须标"后面还有没记上的"。 */
    uart_puts("TRACE RAW count="); uart_hex(ntr);
    uart_puts(" marks="); uart_hex(nmk);
    uart_puts(" status="); uart_hex(st);
    uart_puts("\r\n");

    /* 逐条导出：一条一行（5 个字 = 132 位），上位机按行解析。
       不复用 LA 的 8 位 Raw 通路：两者记录宽度不同，混在一条流里会分不清。 */
    for (i = 0u; i < ntr; ++i) {
        TR_RDIDX = i;
        uart_hex(TR_W0); uart_putc(' ');
        uart_hex(TR_W1); uart_putc(' ');
        uart_hex(TR_W2); uart_putc(' ');
        uart_hex(TR_W3); uart_putc(' ');
        uart_hex(TR_W4);
        uart_putc('\n');
    }

    /* 打点表：每条 6 位十六进制 = {8'b0, index[15:0], value[7:0]} */
    uart_puts("TRACE MARK n="); uart_hex(nmk); uart_putc('\n');
    for (i = 0u; i < nmk; ++i) {
        TR_MIDX = i;
        uart_hex(TR_MRD & 0x00FFFFFFu);
        uart_putc((i + 1u == nmk) ? '\n' : ' ');
    }

    /* 固件自己读出了什么：这是"板子真的处理过这句话"的直接证据，
       也是上位机判 PASS 用的同一份字节（判据与标注必须同源）。 */
    uart_puts("TRACE TEXT hex="); print_byte_values(trace_buf, n);
    uart_puts(" ascii="); print_byte_ascii(trace_buf, n);
    uart_puts(" xor="); uart_hex(x);
    uart_puts(" up="); uart_hex(ups);
    uart_puts(" chars="); uart_hex(n);
    uart_puts("\r\n");
    uart_puts("TRACE_DONE\r\n");
}

#ifdef TRACE_WAVE_ENABLED
/* 0xAB：一次运行里同时抓"每拍波形"与"每条指令"。
   顺序是刻意的：
     ① arm trace  → 窗口从下一条退休指令开始，于是 LA 的 arm 指令本身也在 trace 里；
     ② arm LA     → Core 探针源、每拍 1 样本、触发 = 退休脉冲上升沿；
     ③ 跑处理循环 → 打点、大写化、XOR（与 0xAA 的 phase 0 是同一段代码形状）；
     ④ 等 LA 采满 → 这段自旋也在 trace 里，保证波形窗口**整段**被 trace 覆盖；
     ⑤ 再停 trace → 于是"波形第 k 拍"必能对上"trace 里的某一条"。
   上位机据此用退休脉冲个数对齐，再用数据访问脉冲个数交叉校验。

   **只在 8 KB 镜像里编**：4 KB 装不下（2026-10-24 实测溢出 436 字节），
   而交付工程的固件镜像必须保持原样，不能为了演示去挤掉别的东西。 */
static void trace_and_wave(unsigned int n, unsigned int win) {
    unsigned int i, c, x = 0u, ups = 0u, post, ns, ntr, nmk, st;

    if (n == 0u) n = 1u;
    if (n > TRACE_BUF_MAX) n = TRACE_BUF_MAX;
    /* 窗口档：0/1/2 → 256/512/1024 个后触发样本，3 → 2047（+1 个触发样本 = 2048） */
    post = (win >= 3u) ? 2047u : ((256u << win) - 1u);

    TR_CTRL = 4u;
    LA_CONTROL = 4u;                 /* LA clear */
    LA_SRC = 1u;                     /* Core 内部观测点 */
    LA_DIV = 0u;                     /* 每拍一个样本（capture_engine：div=0 才每拍采一次）*/
    LA_CH_MASK = 0xFFu;
    LA_TR_MASK = LA_PROBE_RETIRE;    /* 触发看 bit7 = 退休脉冲 */
    LA_TR_VALUE = LA_PROBE_RETIRE;
    LA_TR_RISE = LA_PROBE_RETIRE;    /* 上升沿触发 */
    LA_TR_FALL = 0u;
    LA_PRE = 0u; LA_POST = post;
    LA_PAT_CTL = 0u;                 /* 关掉图案发生器：本命令只看 Core */

    /* 先把整句收进 RAM（此时两个窗口都还没开，收字符不进窗口） */
    for (i = 0u; i < n; ++i) trace_buf[i] = (unsigned char)uart_getc();

    TR_CTRL = 1u;                    /* ① trace 先 arm */
    LA_CONTROL = 1u;                 /* ② LA 再 arm：等下一条退休脉冲 */
    for (i = 0u; i < n; ++i) {       /* ③ 处理循环（与 0xAA phase 0 同形） */
        c = trace_buf[i];
        TR_MWR = c & 0xFFu;
        if (c >= 0x61u && c <= 0x7Au) { c -= 0x20u; ups++; }
        trace_buf[i] = (unsigned char)c;
        x ^= c;
    }
    while ((LA_STATUS & 4u) == 0u) { }   /* ④ 等波形窗口采满（这段也在 trace 里） */
    TR_CTRL = 2u;                    /* ⑤ 最后才停 trace */

    /* 波形块先打：上位机按 "LA RAW" / "TRACE RAW" 前缀切分两块 */
    ns = LA_COUNT; if (ns > LA_DEPTH) ns = LA_DEPTH;
    uart_puts("LA RAW count="); uart_hex(ns);
    uart_puts(" trigger="); uart_hex(LA_TR_INDEX);
    uart_puts(" window="); uart_hex(post + 1u);
    uart_puts(" div="); uart_hex(LA_DIV);
    uart_puts("\r\n");
    for (i = 0u; i < ns; ++i) {
        LA_INDEX = i; c = LA_DATA & 0xFFu;
        uart_hex(c);
        uart_putc((i + 1u == ns) ? '\n' : ' ');
    }
    uart_puts("LA_DONE\r\n");

    /* 指令流块：字段与 0xAA 的回包逐字段一致，上位机复用同一套解析 */
    st = TR_STATUS;
    ntr = TR_COUNT; if (ntr > TR_DEPTH) ntr = TR_DEPTH;
    nmk = TR_MARKCNT;
    uart_puts("TRACE RAW count="); uart_hex(ntr);
    uart_puts(" marks="); uart_hex(nmk);
    uart_puts(" status="); uart_hex(st);
    uart_puts("\r\n");
    for (i = 0u; i < ntr; ++i) {
        TR_RDIDX = i;
        uart_hex(TR_W0); uart_putc(' ');
        uart_hex(TR_W1); uart_putc(' ');
        uart_hex(TR_W2); uart_putc(' ');
        uart_hex(TR_W3); uart_putc(' ');
        uart_hex(TR_W4);
        uart_putc('\n');
    }
    uart_puts("TRACE MARK n="); uart_hex(nmk); uart_putc('\n');
    for (i = 0u; i < nmk; ++i) {
        TR_MIDX = i;
        uart_hex(TR_MRD & 0x00FFFFFFu);
        uart_putc((i + 1u == nmk) ? '\n' : ' ');
    }
    uart_puts("TRACE TEXT hex="); print_byte_values(trace_buf, n);
    uart_puts(" ascii="); print_byte_ascii(trace_buf, n);
    uart_puts(" xor="); uart_hex(x);
    uart_puts(" up="); uart_hex(ups);
    uart_puts(" chars="); uart_hex(n);
    uart_puts("\r\n");
    uart_puts("TRACE_DONE\r\n");
}
#endif /* TRACE_WAVE_ENABLED：只有 8 KB 镜像才编这条组合命令 */
#endif /* !FINAL_AUTOSTART：trace_and_report 依赖会阻塞的 uart_getc */

int main(void) {
    GPIO_OUT = 0x5Au;
#if FINAL_AUTOSTART
    capture_and_report(0u, 1u, 0u, 0u, 0u, 1u, 1u, 4u, 4u);
    for (;;) { }
#else
    unsigned int packet[16], i, checksum;
    uart_puts("LA_READY\r\n");
    for (;;) {
        do { packet[0] = uart_getc(); } while (packet[0] != 0xA5u && packet[0] != LA_MIRROR && packet[0] != LA_SRC_CORE && packet[0] != LA_TRACE_CMD
#ifdef TRACE_WAVE_ENABLED
            && packet[0] != LA_TRACE_WAVE
#endif
            );
        checksum = packet[0];
#ifdef TRACE_WAVE_ENABLED
        if (packet[0] == LA_TRACE_WAVE) {
            /* 0xAB：4 字节，[1]=字符数、[2]=波形窗口档、[3]=XOR([1..2])。
               一次回包里既有 8 通道波形、又有逐条指令（见 trace_and_wave 注释）。 */
            for (i = 1u; i < 3u; ++i) { packet[i] = uart_getc(); checksum ^= packet[i]; }
            packet[3] = uart_getc();
            if ((checksum & 0xFFu) != packet[3]) { uart_puts("LA_CONFIG_ERROR\r\n"); continue; }
            trace_and_wave(packet[1], packet[2]);
            uart_puts("LA_READY\r\n");
            continue;
        }
#endif
        if (packet[0] == LA_TRACE_CMD) {
            /* 0xAA：4 字节，[1]=字符数、[2]=阶段、[3]=XOR([1..2])。
               分两个阶段是因为"接收"和"处理"对窗口的价值完全不同：
               接收阶段里 CPU 绝大部分时间在轮询串口状态位，处理阶段才是真正的数据流。 */
            for (i = 1u; i < 3u; ++i) { packet[i] = uart_getc(); checksum ^= packet[i]; }
            packet[3] = uart_getc();
            if ((checksum & 0xFFu) != packet[3]) { uart_puts("LA_CONFIG_ERROR\r\n"); continue; }
            trace_and_report(packet[1], packet[2]);
            uart_puts("LA_READY\r\n");
            continue;
        }
        if (packet[0] == LA_SRC_CORE) {
            /* 0xA8：16 字节，pre/post 各 16 位，[14] 显式指定采集源，[15] 是校验。
               采集源在 Arm 之前写入，因此同一次采样不会跨源。 */
            for (i = 1u; i < 15u; ++i) { packet[i] = uart_getc(); checksum ^= packet[i]; }
            packet[15] = uart_getc();
            if ((checksum & 0xFFu) != packet[15]) { uart_puts("LA_CONFIG_ERROR\r\n"); continue; }
            LA_SRC = packet[14] ? 1u : 0u;
            capture_and_report(packet[1], packet[2], packet[3] | (packet[4] << 8u),
                               packet[5] | (packet[6] << 8u), packet[7], packet[8],
                               packet[9], packet[10] | (packet[11] << 8u),
                               packet[12] | (packet[13] << 8u));
            uart_puts("LA_READY\r\n");
            continue;
        }
        for (i = 1u; i < 13u; ++i) { packet[i] = uart_getc(); if (i < 12u) checksum ^= packet[i]; }
        if ((checksum & 0xFFu) != packet[12]) { uart_puts("LA_CONFIG_ERROR\r\n"); continue; }
        /* 0xA5/0xA7 明确回到 J8 外部源：否则上一次 0xA8 留下的 Core 源会
           静默影响后面的采集，而波形看起来"也是对的"，很难查。 */
        LA_SRC = 0u;
        if (packet[0] == LA_MIRROR) {
            /* 0xA7：13 字节布局不变，只重新定义两个字段——
               [2]        = 每比特采样点数（上位机按波特率与板级时钟算出）
               [10]|[11]  = 16 位 post；镜像模式固定 pre=0，窗口从起始位开始
               其余（sample_div、触发类型/掩码/值）语义与 0xA5 一致。 */
            capture_and_report(4u, packet[2], 0u, packet[5] | (packet[6] << 8u),
                               packet[7], packet[8], packet[9], 0u,
                               packet[10] | (packet[11] << 8u));
        } else {
            capture_and_report(packet[1], packet[2], packet[3] | (packet[4] << 8u),
                               packet[5] | (packet[6] << 8u), packet[7], packet[8],
                               packet[9], packet[10], packet[11]);
        }
        uart_puts("LA_READY\r\n");
    }
#endif
}
