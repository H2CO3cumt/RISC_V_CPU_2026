#include "core_portme.h"
#include <stdarg.h>

static int emit_char(char ch)
{
    uart_send_char(ch);
    return 1;
}

static int emit_repeat(char ch, int count)
{
    int written = 0;
    while (count-- > 0) written += emit_char(ch);
    return written;
}

static int emit_string(const char *text, int width)
{
    int len = 0;
    int written = 0;
    const char *p = text;
    if (text == NULL) text = "(null)";
    p = text;
    while (p[len] != '\0') len++;
    written += emit_repeat(' ', width > len ? width - len : 0);
    while (*p != '\0') written += emit_char(*p++);
    return written;
}

static int emit_unsigned(unsigned long value, unsigned int base, int width,
                         int zero_pad, int upper)
{
    char digits[16];
    const char *alphabet = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    int used = 0;
    int written = 0;
    do {
        digits[used++] = alphabet[value % base];
        value /= base;
    } while (value != 0 && used < (int)sizeof(digits));
    written += emit_repeat(zero_pad ? '0' : ' ', width > used ? width - used : 0);
    while (used > 0) written += emit_char(digits[--used]);
    return written;
}

int ee_printf(const char *fmt, ...)
{
    va_list args;
    int written = 0;
    va_start(args, fmt);
    while (*fmt != '\0') {
        int zero_pad = 0;
        int width = 0;
        int is_long = 0;
        char spec;
        if (*fmt != '%') {
            written += emit_char(*fmt++);
            continue;
        }
        fmt++;
        if (*fmt == '0') { zero_pad = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') {
            width = width * 10 + (*fmt - '0');
            fmt++;
        }
        if (*fmt == 'l') { is_long = 1; fmt++; }
        spec = *fmt != '\0' ? *fmt++ : '\0';
        if (spec == 's') {
            written += emit_string(va_arg(args, const char *), width);
        } else if (spec == 'c') {
            written += emit_char((char)va_arg(args, int));
        } else if (spec == 'd' || spec == 'i') {
            long value = is_long ? va_arg(args, long) : (long)va_arg(args, int);
            unsigned long magnitude;
            if (value < 0) {
                written += emit_char('-');
                if (width > 0) width--;
                magnitude = (unsigned long)(-(value + 1)) + 1ul;
            } else {
                magnitude = (unsigned long)value;
            }
            written += emit_unsigned(magnitude, 10u, width, zero_pad, 0);
        } else if (spec == 'u' || spec == 'x' || spec == 'X') {
            unsigned long value = is_long ? va_arg(args, unsigned long)
                                          : (unsigned long)va_arg(args, unsigned int);
            written += emit_unsigned(value, spec == 'u' ? 10u : 16u,
                                     width, zero_pad, spec == 'X');
        } else if (spec == '%') {
            written += emit_char('%');
        } else {
            written += emit_char('%');
            if (spec != '\0') written += emit_char(spec);
        }
    }
    va_end(args);
    return written;
}
