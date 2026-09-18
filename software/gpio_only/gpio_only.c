#define GPIO_OUT (*(volatile unsigned int *)0x10001000u)
#define RESULT   (*(volatile unsigned int *)0x00000300u)

int main(void)
{
    // The RAM result is written before the final observable GPIO Store.  The
    // Task 17 harness uses that final Store as its deterministic snapshot.
    RESULT = 0x13579BDFu;
    GPIO_OUT = 0xA5u;
    return 0;
}
