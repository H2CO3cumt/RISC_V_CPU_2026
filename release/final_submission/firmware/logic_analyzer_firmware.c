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
static unsigned int decode_uart(const unsigned int *s, unsigned int n, unsigned int bit_samples) {
    unsigned int i = 1u, count = 0u;
    while (i + bit_samples * 9u < n) {
        if ((s[i - 1u] & 1u) != 0u && (s[i] & 1u) == 0u) {
            unsigned int bit, value = 0u;
            for (bit = 0u; bit < 8u; ++bit)
                value |= ((s[i + bit_samples * (bit + 1u)] & 1u) != 0u) << bit;
            if ((s[i + bit_samples * 9u] & 1u) != 0u) { uart_hex(value); ++count; }
            i += bit_samples * 10u;
        } else ++i;
    }
    return count;
}
static unsigned int decode_spi(const unsigned int *s, unsigned int n) {
    unsigned int i, previous = 0u, bits = 0u, value = 0u, count = 0u;
    for (i = 0u; i < n; ++i) {
        unsigned int active = (s[i] & 4u) == 0u;
        unsigned int rising = previous == 0u && (s[i] & 1u) != 0u;
        previous = (s[i] & 1u) != 0u;
        if (active && rising) {
            value = ((value << 1u) | ((s[i] >> 1u) & 1u)) & 0xFFu;
            if (++bits == 8u) { uart_hex(value); ++count; bits = 0u; value = 0u; }
        } else if (!active) { bits = 0u; value = 0u; }
    }
    return count;
}

static void capture_and_report(unsigned int mode, unsigned int data,
                               unsigned int pattern_div, unsigned int sample_div,
                               unsigned int trigger_type, unsigned int trigger_mask,
                               unsigned int trigger_value, unsigned int pre,
                               unsigned int post) {
    unsigned int i, n, bit_samples, raw[256];
    LA_CONTROL = 4u;
    LA_DIV = sample_div; LA_CH_MASK = 0xFFu;
    LA_TR_MASK = trigger_mask; LA_TR_VALUE = trigger_value;
    LA_TR_RISE = trigger_type == 1u ? trigger_mask : 0u;
    LA_TR_FALL = trigger_type == 2u ? trigger_mask : 0u;
    LA_PRE = pre; LA_POST = post;
    LA_PAT_DATA = data; LA_PAT_DIV = pattern_div;
    LA_PAT_CTL = (mode & 3u) | 4u;
    LA_CONTROL = 1u;
    while ((LA_STATUS & 4u) == 0u) { }
    n = LA_COUNT; if (n > 256u) n = 256u;
    uart_puts("LA RAW count="); uart_hex(n); uart_puts(" trigger="); uart_hex(LA_TR_INDEX); uart_puts("\r\n");
    for (i = 0u; i < n; ++i) {
        LA_INDEX = i; raw[i] = LA_DATA & 0xFFu; uart_hex(raw[i]);
        uart_putc((i + 1u == n) ? '\n' : ' ');
    }
    bit_samples = (pattern_div + 1u) / (sample_div + 1u);
    if (bit_samples == 0u) bit_samples = 1u;
    uart_puts("UART:"); uart_hex(decode_uart(raw, n, bit_samples));
    uart_puts(" SPI:"); uart_hex(decode_spi(raw, n)); uart_puts("\r\nLA_DONE\r\n");
}

int main(void) {
    GPIO_OUT = 0x5Au;
#if FINAL_AUTOSTART
    capture_and_report(0u, 1u, 0u, 0u, 0u, 1u, 1u, 4u, 4u);
    for (;;) { }
#else
    unsigned int packet[13], i, checksum;
    uart_puts("LA_READY\r\n");
    for (;;) {
        do { packet[0] = uart_getc(); } while (packet[0] != 0xA5u);
        checksum = packet[0];
        for (i = 1u; i < 13u; ++i) { packet[i] = uart_getc(); if (i < 12u) checksum ^= packet[i]; }
        if ((checksum & 0xFFu) != packet[12]) { uart_puts("LA_CONFIG_ERROR\r\n"); continue; }
        capture_and_report(packet[1], packet[2], packet[3] | (packet[4] << 8u),
                           packet[5] | (packet[6] << 8u), packet[7], packet[8],
                           packet[9], packet[10], packet[11]);
        uart_puts("LA_READY\r\n");
    }
#endif
}
