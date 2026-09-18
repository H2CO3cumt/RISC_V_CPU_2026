#define UART_TXDATA (*(volatile unsigned int *)0x10000000u)
#define UART_STATUS (*(volatile unsigned int *)0x10000004u)
#define UART_TX_READY 0x00000001u
#define RESULT (*(volatile unsigned int *)0x00000300u)

static void uart_putc(char ch)
{
    while ((UART_STATUS & UART_TX_READY) == 0u) {
    }
    UART_TXDATA = (unsigned int)(unsigned char)ch;
}

int main(void)
{
    RESULT = 0x2468ACE0u;
    uart_putc('U');
    uart_putc('\n');
    return 0;
}
