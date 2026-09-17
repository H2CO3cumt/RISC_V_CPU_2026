/* TASK3: minimal RV32I freestanding program. */

volatile int result;

__attribute__((noinline)) int add(int a, int b)
{
    return a + b;
}

int main(void)
{
    int sum = 0;
    int i;

    for (i = 0; i < 4; i++) {
        sum = add(sum, i);
    }

    result = sum;

    while (1) {
        /* A bare-metal program must not return to an operating system. */
    }
}
