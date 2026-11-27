// STELLAR Prime Generator in Stellar C - the same program as APPLICATIONS/Prime-Gen-v07.lst
// (asks for a low and a high limit and prints the primes between them).

u16 readnum() {                    // digits with echo; backspace rubs one out; Enter ends
    u16 v = 0;
    u16 len = 0;
    u16 c;
    while (1) {
        c = getc();
        if (c == 13) break;
        if (c == 8 || c == 127) {
            if (len != 0) { len--; v = v / 10; print("\b \b"); }
        } else if (c >= '0' && c <= '9') {
            putc(c);
            v = v * 10 + c - '0';
            len++;
        }
    }
    print("\r\n");
    return v;
}

void main() {
    u16 low, high, n, d, q;
    print("STELLAR Prime Generator\r\n");
    print("Low limit:  ");
    low = readnum();
    print("High limit: ");
    high = readnum();
    print("Primes:\r\n");
    n = low;
    if (n % 2 == 0) n++;           // odd numbers only, as v07
    while (n <= high) {
        if (n >= 1) {
            if (n < 8) { printu(n); putc(' '); }
            else {
                d = 3;
                while (1) {
                    q = n / d;
                    if (n % d == 0) break;          // the same DIVXY: its remainder
                    if (q < d) { printu(n); putc(' '); break; }
                    d += 2;
                }
            }
        }
        n += 2;
    }
    print("\r\nDone.\r\n");
}
