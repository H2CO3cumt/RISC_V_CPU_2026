/* Task 14 first GCC smoke program: expected result is 45. */

volatile int result;

__attribute__((noinline)) int add(int lhs, int rhs)
{
    return lhs + rhs;
}

int main(void)
{
    int sum = 0;
    int i;

    for (i = 0; i < 10; i++) {
        sum = add(sum, i);
    }

    result = sum;
    return 0;
}
