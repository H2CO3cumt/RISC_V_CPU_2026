/* Task 14: array, function call, loop, if/else, .data and .bss. */

volatile int seed = 3;
volatile int result;
volatile int false_result;

__attribute__((noinline)) int transform(int value)
{
    return value + seed;
}

int main(void)
{
    int values[4];
    int i;
    int sum = 0;

    for (i = 0; i < 4; i++) {
        values[i] = transform(i);
    }

    for (i = 0; i < 4; i++) {
        sum += values[i];
    }

    if (sum == 18)
        result = sum;
    else
        result = -1;

    if (sum == 17)
        false_result = sum;
    else
        false_result = -1;

    return 0;
}
