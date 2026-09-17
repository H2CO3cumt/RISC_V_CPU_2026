#define UART_TXDATA (*(volatile unsigned int *)0x10000000u)
#define UART_STATUS (*(volatile unsigned int *)0x10000004u)
#define GPIO_OUT    (*(volatile unsigned int *)0x10001000u)

#define UART_TX_READY 0x00000001u

static void uart_putc(char ch)
{
    while ((UART_STATUS & UART_TX_READY) == 0u) {
    }
    UART_TXDATA = (unsigned int)(unsigned char)ch;
}

static void uart_puts(const char *text)
{
    while (*text != '\0') {
        uart_putc(*text);
        text++;
    }
}

int main(void)
{
    GPIO_OUT = 0xAAu;
    for (;;) {
        // Keep the demo observable after download: each pass waits for the
        // UART transmitter and emits a complete line before repeating.
        uart_puts("Hello RISC-V!\r\n");
    }
}
